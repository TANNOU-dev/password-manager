import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import '../../core/lock/lock_controller.dart';
import '../../core/utils/password_strength.dart';
import '../../core/utils/ssh_key.dart';
import '../../core/utils/totp.dart';
import '../../data/api/api_client.dart';
import '../../data/models/cipher.dart';
import '../../data/vault_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/strength_meter.dart';
import '../generator/generator_sheet.dart';
import 'folder_sheet.dart';

/// Création et modification d'un élément.
///
/// Un seul écran pour les deux : `existing` nul signifie création. Le type ne
/// change plus après coup — passer une carte bancaire en note perdrait des
/// champs sans qu'on sache lesquels.
class ItemEditScreen extends StatefulWidget {
  const ItemEditScreen({
    super.key,
    this.existing,
    this.type,
    this.folderId,
  }) : assert(existing != null || type != null,
            'Il faut soit un élément à modifier, soit un type à créer');

  final CipherItem? existing;
  final CipherType? type;
  final String? folderId;

  @override
  State<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends State<ItemEditScreen> {
  late final CipherType _type;
  late final bool _isNew;

  // Champs communs
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  String? _folderId;
  bool _favorite = false;
  bool _reprompt = false;

  // Identifiant
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _totpController = TextEditingController();
  final List<_UriDraft> _uris = [];
  bool _obscurePassword = true;

  // Carte
  final _cardholderController = TextEditingController();
  final _numberController = TextEditingController();
  final _expMonthController = TextEditingController();
  final _expYearController = TextEditingController();
  final _codeController = TextEditingController();

  // Identité
  final Map<String, TextEditingController> _identity = {
    for (final key in [
      'title', 'firstName', 'middleName', 'lastName', 'company', 'email',
      'phone', 'username', 'ssn', 'passportNumber', 'licenseNumber',
      'address1', 'address2', 'city', 'state', 'postalCode', 'country',
    ])
      key: TextEditingController(),
  };

  // Clé SSH
  final _privateKeyController = TextEditingController();
  final _publicKeyController = TextEditingController();
  String _fingerprint = '';
  bool _obscurePrivateKey = true;
  bool _generating = false;

  // Champs personnalisés
  final List<_FieldDraft> _fields = [];

  bool _busy = false;
  String? _error;

  /// Mot de passe d'origine, pour savoir s'il a changé et alimenter
  /// l'historique. Un simple booléen ne suffirait pas : l'utilisateur peut
  /// modifier puis revenir à la valeur initiale.
  String _originalPassword = '';

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _isNew = existing == null;
    _type = existing?.type ?? widget.type!;
    _folderId = existing?.folderId ?? widget.folderId;
    _favorite = existing?.favorite ?? false;
    _reprompt = existing?.reprompt ?? false;

    final data = existing?.data;
    if (data != null) {
      _nameController.text = data.name;
      _notesController.text = data.notes;
      _fields.addAll(data.fields.map(_FieldDraft.from));
    }

    switch (data) {
      case LoginData d:
        _usernameController.text = d.username;
        _passwordController.text = d.password;
        _originalPassword = d.password;
        _totpController.text = d.totp;
        _uris.addAll(d.uris.map(_UriDraft.from));
      case CardData d:
        _cardholderController.text = d.cardholderName;
        _numberController.text = d.number;
        _expMonthController.text = d.expMonth;
        _expYearController.text = d.expYear;
        _codeController.text = d.code;
      case IdentityData d:
        _identity['title']!.text = d.title;
        _identity['firstName']!.text = d.firstName;
        _identity['middleName']!.text = d.middleName;
        _identity['lastName']!.text = d.lastName;
        _identity['company']!.text = d.company;
        _identity['email']!.text = d.email;
        _identity['phone']!.text = d.phone;
        _identity['username']!.text = d.username;
        _identity['ssn']!.text = d.ssn;
        _identity['passportNumber']!.text = d.passportNumber;
        _identity['licenseNumber']!.text = d.licenseNumber;
        _identity['address1']!.text = d.address1;
        _identity['address2']!.text = d.address2;
        _identity['city']!.text = d.city;
        _identity['state']!.text = d.state;
        _identity['postalCode']!.text = d.postalCode;
        _identity['country']!.text = d.country;
      case SshKeyData d:
        _privateKeyController.text = d.privateKey;
        _publicKeyController.text = d.publicKey;
        _fingerprint = d.keyFingerprint;
      case SecureNoteData():
      case null:
        break;
    }

    if (_isNew && _type == CipherType.login) {
      // Une entrée neuve part avec un champ d'adresse vide : c'est le cas
      // courant, autant éviter un appui de plus.
      _uris.add(_UriDraft());
    }

    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [
      _nameController, _notesController, _usernameController,
      _passwordController, _totpController, _cardholderController,
      _numberController, _expMonthController, _expYearController,
      _codeController, _privateKeyController, _publicKeyController,
    ]) {
      c.dispose();
    }
    for (final c in _identity.values) {
      c.dispose();
    }
    for (final u in _uris) {
      u.dispose();
    }
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  // ==================== ENREGISTREMENT ====================

  CipherData _buildData() {
    final name = _nameController.text.trim();
    final notes = _notesController.text;
    final fields = _fields
        .where((f) => f.nameController.text.trim().isNotEmpty)
        .map((f) => f.toField())
        .toList(growable: false);

    switch (_type) {
      case CipherType.login:
        final uris = _uris
            .where((u) => u.controller.text.trim().isNotEmpty)
            .map((u) => u.toUri())
            .toList(growable: false);

        var login = LoginData(
          name: name,
          username: _usernameController.text.trim(),
          password: _originalPassword,
          totp: _totpController.text.trim(),
          notes: notes,
          uris: uris,
          fields: fields,
          passwordHistory: (widget.existing?.data as LoginData?)?.passwordHistory ??
              const [],
          passwordUpdatedAt:
              (widget.existing?.data as LoginData?)?.passwordUpdatedAt,
        );

        // Passe par withNewPassword pour que l'ancien mot de passe entre dans
        // l'historique et que la date de changement soit posée.
        final typed = _passwordController.text;
        if (typed != _originalPassword) {
          login = login.withNewPassword(typed);
        } else if (_isNew && typed.isNotEmpty) {
          login = login.copyWith(
            password: typed,
            passwordUpdatedAt: DateTime.now().toUtc(),
          );
        }
        return login;

      case CipherType.card:
        return CardData(
          name: name,
          cardholderName: _cardholderController.text.trim(),
          number: _numberController.text.replaceAll(' ', '').trim(),
          expMonth: _expMonthController.text.trim(),
          expYear: _expYearController.text.trim(),
          code: _codeController.text.trim(),
          notes: notes,
          fields: fields,
        );

      case CipherType.identity:
        String v(String key) => _identity[key]!.text.trim();
        return IdentityData(
          name: name,
          title: v('title'),
          firstName: v('firstName'),
          middleName: v('middleName'),
          lastName: v('lastName'),
          company: v('company'),
          email: v('email'),
          phone: v('phone'),
          username: v('username'),
          ssn: v('ssn'),
          passportNumber: v('passportNumber'),
          licenseNumber: v('licenseNumber'),
          address1: v('address1'),
          address2: v('address2'),
          city: v('city'),
          state: v('state'),
          postalCode: v('postalCode'),
          country: v('country'),
          notes: notes,
          fields: fields,
        );

      case CipherType.secureNote:
        return SecureNoteData(name: name, notes: notes, fields: fields);

      case CipherType.sshKey:
        final publicKey = _publicKeyController.text.trim();
        return SshKeyData(
          name: name,
          privateKey:
              SshKeys.normalizePrivateKey(_privateKeyController.text),
          publicKey: publicKey,
          // Recalculée à l'enregistrement plutôt que reprise du champ :
          // si l'utilisateur colle une autre clé publique, l'empreinte
          // affichée doit suivre, sans quoi elle désignerait l'ancienne.
          keyFingerprint:
              SshKeys.fingerprintOfPublicKey(publicKey) ?? _fingerprint,
          notes: notes,
          fields: fields,
        );
    }
  }

  String? _validate() {
    if (_nameController.text.trim().isEmpty) {
      return 'Donnez un nom à cet élément.';
    }
    final totp = _totpController.text.trim();
    if (totp.isNotEmpty && !Totp.isValid(totp)) {
      return 'Le secret TOTP est illisible. Attendu : une clé en base32 ou une '
          'URI otpauth://';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final base = widget.existing ??
          CipherItem(data: _buildData(), folderId: _folderId);
      await context.read<VaultRepository>().saveItem(
            base.copyWith(
              data: _buildData(),
              folderId: _folderId,
              clearFolder: _folderId == null,
              favorite: _favorite,
              reprompt: _reprompt,
            ),
          );
      if (!mounted) return;
      AppFeedback.show(
        context,
        _isNew ? 'Élément ajouté' : 'Modifications enregistrées',
        icon: Icons.check_rounded,
      );
      Navigator.of(context).pop();
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ==================== ACTIONS ====================

  Future<void> _openGenerator() async {
    final generated = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const GeneratorSheet(),
    );
    if (generated == null || !mounted) return;
    _passwordController.text = generated;
    setState(() {});
  }

  Future<void> _pickFolder() async {
    final result = await showModalBottomSheet<FolderSelection>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FolderSheet(selectedId: _folderId, pickOnly: true),
    );
    if (result == null || !mounted) return;
    setState(() => _folderId = result.folderId);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final repo = context.watch<VaultRepository>();
    final folderName = _folderId == null
        ? 'Sans dossier'
        : repo.folders
                .where((f) => f.id == _folderId)
                .map((f) => f.name)
                .firstOrNull ??
            'Sans dossier';

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(_isNew ? 'Nouveau — ${_type.label}' : 'Modifier'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, 140),
        children: [
          TextField(
            controller: _nameController,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Nom',
              hintText: switch (_type) {
                CipherType.login => 'GitHub',
                CipherType.card => 'Carte Ecobank',
                CipherType.identity => 'Identité principale',
                CipherType.secureNote => 'Codes de récupération',
                CipherType.sshKey => 'Clé de déploiement',
              },
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Gap.xxl),

          ...switch (_type) {
            CipherType.login => _loginFields(),
            CipherType.card => _cardFields(),
            CipherType.identity => _identityFields(),
            CipherType.secureNote => _noteFields(),
            CipherType.sshKey => _sshKeyFields(),
          },

          const SizedBox(height: Gap.xxl),
          _customFieldsSection(),

          if (_type != CipherType.secureNote) ...[
            const SizedBox(height: Gap.xxl),
            const SectionLabel('Notes'),
            TextField(
              controller: _notesController,
              enabled: !_busy,
              maxLines: 4,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Informations complémentaires (chiffrées)',
              ),
            ),
          ],

          const SizedBox(height: Gap.xxl),
          const SectionLabel('Rangement'),
          HairlineCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Dossier'),
                  subtitle: Text(folderName),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _busy ? null : _pickFolder,
                ),
                Divider(height: 1, color: c.hairline),
                SwitchListTile(
                  value: _favorite,
                  onChanged: _busy ? null : (v) => setState(() => _favorite = v),
                  secondary: Icon(
                    Icons.star_outline_rounded,
                    color: _favorite ? c.warning : null,
                  ),
                  title: const Text('Favori'),
                  subtitle: const Text('Remonte en tête de la liste'),
                ),
                Divider(height: 1, color: c.hairline),
                SwitchListTile(
                  value: _reprompt,
                  onChanged: _busy ? null : (v) => setState(() => _reprompt = v),
                  secondary: const Icon(Icons.password_rounded),
                  title: const Text('Redemander le mot de passe maître'),
                  subtitle: const Text(
                    'Pour les éléments les plus sensibles',
                  ),
                ),
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: Gap.xl),
            InlineError(message: _error!),
          ],
        ],
      ),
      bottomNavigationBar: _SaveBar(
        busy: _busy,
        enabled: _nameController.text.trim().isNotEmpty,
        isNew: _isNew,
        onSave: _save,
      ),
    );
  }

  // ==================== SECTIONS PAR TYPE ====================

  List<Widget> _loginFields() {
    final strength = PasswordStrengthEvaluator.evaluate(_passwordController.text);

    return [
      const SectionLabel('Accès'),
      TextField(
        controller: _usernameController,
        enabled: !_busy,
        autocorrect: false,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(
          labelText: 'Identifiant ou e-mail',
          prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
        ),
      ),
      const SizedBox(height: Gap.md),
      TextField(
        controller: _passwordController,
        enabled: !_busy,
        obscureText: _obscurePassword,
        autocorrect: false,
        enableSuggestions: false,
        style: SecretText.of(context),
        decoration: InputDecoration(
          labelText: 'Mot de passe',
          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: _obscurePassword ? 'Afficher' : 'Masquer',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
              ),
              IconButton(
                tooltip: 'Générer',
                onPressed: _busy ? null : _openGenerator,
                icon: Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: context.palette.primary,
                ),
              ),
              const SizedBox(width: Gap.xs),
            ],
          ),
        ),
      ),
      if (_passwordController.text.isNotEmpty) ...[
        const SizedBox(height: Gap.md),
        StrengthMeter(strength: strength),
      ],

      const SizedBox(height: Gap.xxl),
      SectionLabel(
        'Code à usage unique',
        trailing: Text(
          'TOTP',
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: context.palette.accent, fontSize: 11),
        ),
      ),
      TextField(
        controller: _totpController,
        enabled: !_busy,
        autocorrect: false,
        style: SecretText.of(context, size: 14),
        decoration: InputDecoration(
          labelText: 'Clé secrète',
          hintText: 'JBSWY3DPEHPK3PXP ou otpauth://…',
          prefixIcon: const Icon(Icons.timer_outlined, size: 20),
          helperText: 'Le code est calculé sur l’appareil, hors ligne.',
          suffixIcon: _totpController.text.trim().isEmpty
              ? null
              : Icon(
                  Totp.isValid(_totpController.text.trim())
                      ? Icons.check_rounded
                      : Icons.error_outline_rounded,
                  size: 20,
                  color: Totp.isValid(_totpController.text.trim())
                      ? context.palette.success
                      : context.palette.danger,
                ),
        ),
        onChanged: (_) => setState(() {}),
      ),

      const SizedBox(height: Gap.xxl),
      SectionLabel(
        'Adresses',
        trailing: TextButton.icon(
          onPressed: _busy
              ? null
              : () => setState(() => _uris.add(_UriDraft())),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Ajouter'),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
      // Clé sur l'identité du brouillon, pas sur sa position.
      //
      // Sans elle, Flutter apparie les éléments par rang : retirer la ligne i
      // fait hériter l'élément de rang i du brouillon suivant. Il garde alors
      // l'état de l'ancienne ligne — sélection, position du curseur, zone de
      // composition du clavier — sur un texte qui n'est plus le sien.
      for (final draft in _uris)
        Padding(
          key: ObjectKey(draft),
          padding: const EdgeInsets.only(bottom: Gap.md),
          child: _UriRow(
            draft: draft,
            enabled: !_busy,
            onRemove: () => setState(() {
              _uris.remove(draft);
              draft.dispose();
            }),
            onChanged: () => setState(() {}),
          ),
        ),
      if (_uris.isEmpty)
        Text(
          'Aucune adresse. Elles serviront au remplissage automatique.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: context.palette.textTertiary),
        ),
    ];
  }

  List<Widget> _cardFields() {
    return [
      const SectionLabel('Carte'),
      TextField(
        controller: _cardholderController,
        enabled: !_busy,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          labelText: 'Titulaire',
          prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
        ),
      ),
      const SizedBox(height: Gap.md),
      TextField(
        controller: _numberController,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        style: SecretText.of(context),
        decoration: const InputDecoration(
          labelText: 'Numéro',
          prefixIcon: Icon(Icons.credit_card_rounded, size: 20),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: Gap.md),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _expMonthController,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              maxLength: 2,
              style: SecretText.of(context),
              decoration: const InputDecoration(
                labelText: 'Mois',
                hintText: 'MM',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: TextField(
              controller: _expYearController,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              maxLength: 4,
              style: SecretText.of(context),
              decoration: const InputDecoration(
                labelText: 'Année',
                hintText: 'AAAA',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: TextField(
              controller: _codeController,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              style: SecretText.of(context),
              decoration: const InputDecoration(
                labelText: 'CVV',
                counterText: '',
              ),
            ),
          ),
        ],
      ),
      if (_numberController.text.isNotEmpty) ...[
        const SizedBox(height: Gap.md),
        Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: 14, color: context.palette.textTertiary),
            const SizedBox(width: Gap.sm),
            Text(
              'Réseau détecté : ${CardData(name: '', number: _numberController.text).inferredBrand}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: context.palette.textTertiary),
            ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _identityFields() {
    Widget field(
      String key,
      String label, {
      bool obscure = false,
      TextInputType? keyboard,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Gap.md),
        child: TextField(
          controller: _identity[key],
          enabled: !_busy,
          obscureText: obscure,
          keyboardType: keyboard,
          style: obscure ? SecretText.of(context) : null,
          decoration: InputDecoration(labelText: label),
        ),
      );
    }

    return [
      const SectionLabel('État civil'),
      Row(
        children: [
          Expanded(child: field('title', 'Civilité')),
          const SizedBox(width: Gap.md),
          Expanded(flex: 2, child: field('firstName', 'Prénom')),
        ],
      ),
      field('middleName', 'Deuxième prénom'),
      field('lastName', 'Nom'),
      field('company', 'Société'),

      const SizedBox(height: Gap.lg),
      const SectionLabel('Contact'),
      field('email', 'E-mail', keyboard: TextInputType.emailAddress),
      field('phone', 'Téléphone', keyboard: TextInputType.phone),
      field('username', 'Identifiant'),

      const SizedBox(height: Gap.lg),
      const SectionLabel('Adresse'),
      field('address1', 'Adresse'),
      field('address2', 'Complément'),
      Row(
        children: [
          Expanded(flex: 2, child: field('city', 'Ville')),
          const SizedBox(width: Gap.md),
          Expanded(child: field('postalCode', 'Code postal')),
        ],
      ),
      Row(
        children: [
          Expanded(child: field('state', 'Région')),
          const SizedBox(width: Gap.md),
          Expanded(child: field('country', 'Pays')),
        ],
      ),

      const SizedBox(height: Gap.lg),
      // Masqués à la saisie comme à la lecture : ce sont les données les plus
      // sensibles d'une fiche identité.
      const SectionLabel('Pièces d’identité'),
      field('ssn', 'Numéro de sécurité sociale', obscure: true),
      field('passportNumber', 'Passeport', obscure: true),
      field('licenseNumber', 'Permis de conduire', obscure: true),
    ];
  }

  /// Tire une paire et remplit les trois champs.
  ///
  /// Écrase sans demander si les champs sont vides ; sinon on confirme. Une clé
  /// privée remplacée par mégarde est irrécupérable — et si elle est déjà
  /// déposée sur un serveur, l'accès l'est aussi.
  Future<void> _generateKey() async {
    if (_privateKeyController.text.trim().isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remplacer la clé ?'),
          content: const Text(
            'La clé privée actuelle sera perdue. Si elle est déjà installée '
            'sur un serveur, vous n’y accéderez plus avec cette entrée.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remplacer'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _generating = true);
    try {
      // Le nom de l'entrée sert de commentaire : c'est lui qu'on relira dans un
      // authorized_keys pour savoir à quoi la ligne correspond.
      final comment = _nameController.text.trim();
      final pair = await SshKeys.generateEd25519(comment: comment);
      if (!mounted) return;
      setState(() {
        _privateKeyController.text = pair.privateKey;
        _publicKeyController.text = pair.publicKey;
        _fingerprint = pair.fingerprint;
        _obscurePrivateKey = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Génération impossible : $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// Charge une clé existante depuis un fichier (`id_ed25519`, `.pub`).
  ///
  /// Le cas courant : une clé déjà installée sur des serveurs, qu'on veut mettre
  /// à l'abri sans la remplacer. Un fichier privé suffit — la clé publique et
  /// l'empreinte en sont dérivées.
  Future<void> _importKeyFile() async {
    final lock = context.read<LockController>();
    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      // Même précaution que pour l'import de coffre : le sélecteur fait passer
      // l'app en arrière-plan, ce qui verrouillerait le coffre en cours d'édition.
      final result = await lock.duringExcursion(
        () => FilePicker.platform.pickFiles(withData: true),
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      final file = result.files.single;
      final String content;
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        setState(() => _error = 'Fichier illisible.');
        return;
      }

      final pair = SshKeys.readKeyFile(content);
      if (!mounted) return;
      setState(() {
        // Une clé publique seule ne doit pas effacer une privée déjà saisie :
        // les deux moitiés peuvent arriver par deux fichiers successifs.
        if (pair.privateKey.isNotEmpty) _privateKeyController.text = pair.privateKey;
        _publicKeyController.text = pair.publicKey;
        _fingerprint = pair.fingerprint;
        _obscurePrivateKey = true;
        if (_nameController.text.trim().isEmpty) {
          final comment = SshKeys.commentOfPublicKey(pair.publicKey);
          if (comment.isNotEmpty) _nameController.text = comment;
        }
      });
    } on SshKeyException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Lecture impossible : $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// Met l'empreinte à jour pendant la frappe, pour que coller une clé publique
  /// donne un retour immédiat : une empreinte qui apparaît confirme que la clé
  /// est bien formée, sans avoir à enregistrer pour le découvrir.
  void _onPublicKeyChanged(String value) {
    final computed = SshKeys.fingerprintOfPublicKey(value);
    if (computed != _fingerprint) setState(() => _fingerprint = computed ?? '');
  }

  List<Widget> _sshKeyFields() {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final hasKey = _privateKeyController.text.trim().isNotEmpty ||
        _publicKeyController.text.trim().isNotEmpty;

    return [
      SectionLabel(
        'Paire de clés',
        trailing: TextButton.icon(
          onPressed: _busy || _generating ? null : _generateKey,
          icon: _generating
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_rounded, size: 16),
          label: Text(_generating ? 'Génération…' : 'Générer'),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),

      if (!hasKey) ...[
        HairlineCard(
          sunken: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.terminal_rounded, size: 16, color: c.accent),
                  const SizedBox(width: Gap.sm),
                  Text('Ed25519', style: text.titleSmall),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Text(
                'Générez une paire, importez un fichier de clé existant, ou '
                'collez-la ci-dessous. Le format est celui d’OpenSSH : la clé '
                'publique se colle telle quelle dans un authorized_keys.',
                style: text.bodySmall?.copyWith(color: c.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
      ],

      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _busy || _generating ? null : _importKeyFile,
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          label: const Text('Importer un fichier de clé'),
        ),
      ),
      const SizedBox(height: Gap.lg),

      TextField(
        controller: _privateKeyController,
        enabled: !_busy,
        obscureText: _obscurePrivateKey,
        autocorrect: false,
        enableSuggestions: false,
        maxLines: _obscurePrivateKey ? 1 : 10,
        minLines: 1,
        style: SecretText.of(context),
        decoration: InputDecoration(
          labelText: 'Clé privée',
          hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
          alignLabelWithHint: true,
          suffixIcon: IconButton(
            tooltip: _obscurePrivateKey ? 'Afficher' : 'Masquer',
            onPressed: () =>
                setState(() => _obscurePrivateKey = !_obscurePrivateKey),
            icon: Icon(
              _obscurePrivateKey
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 20,
            ),
          ),
        ),
      ),

      const SizedBox(height: Gap.lg),
      TextField(
        controller: _publicKeyController,
        enabled: !_busy,
        autocorrect: false,
        enableSuggestions: false,
        maxLines: 4,
        minLines: 2,
        style: SecretText.of(context),
        decoration: const InputDecoration(
          labelText: 'Clé publique',
          hintText: 'ssh-ed25519 AAAA…',
          alignLabelWithHint: true,
        ),
        onChanged: _onPublicKeyChanged,
      ),

      const SizedBox(height: Gap.md),
      if (_fingerprint.isNotEmpty)
        HairlineCard(
          sunken: true,
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.sm,
          ),
          child: InfoRow(
            label: 'Empreinte',
            value: _fingerprint,
            monospace: true,
            copyable: true,
            copyLabel: 'Empreinte',
          ),
        )
      else if (_publicKeyController.text.trim().isNotEmpty)
        Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 14, color: c.textTertiary),
            const SizedBox(width: Gap.xs),
            Expanded(
              child: Text(
                'Clé publique non reconnue : l’empreinte reste vide.',
                style: text.bodySmall?.copyWith(color: c.textTertiary),
              ),
            ),
          ],
        ),
    ];
  }

  List<Widget> _noteFields() {
    return [
      const SectionLabel('Contenu'),
      TextField(
        controller: _notesController,
        enabled: !_busy,
        maxLines: 12,
        minLines: 6,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Texte libre. Chiffré comme le reste du coffre.',
          alignLabelWithHint: true,
        ),
      ),
    ];
  }

  Widget _customFieldsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'Champs personnalisés',
          trailing: TextButton.icon(
            onPressed:
                _busy ? null : () => setState(() => _fields.add(_FieldDraft())),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Ajouter'),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        // Même raison que pour les adresses : voir le commentaire là-bas.
        for (final draft in _fields)
          Padding(
            key: ObjectKey(draft),
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: _FieldRow(
              draft: draft,
              enabled: !_busy,
              onRemove: () => setState(() {
                _fields.remove(draft);
                draft.dispose();
              }),
              onChanged: () => setState(() {}),
            ),
          ),
        if (_fields.isEmpty)
          Text(
            'Pour ce qui n’entre dans aucun champ : question secrète, numéro '
            'de client, code PIN…',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: context.palette.textTertiary),
          ),
      ],
    );
  }
}

// ==================== BROUILLONS ====================

/// État mutable d'une adresse en cours de saisie.
class _UriDraft {
  final TextEditingController controller;
  UriMatchType match;

  _UriDraft({String uri = '', this.match = UriMatchType.domain})
      : controller = TextEditingController(text: uri);

  factory _UriDraft.from(LoginUri uri) =>
      _UriDraft(uri: uri.uri, match: uri.match);

  LoginUri toUri() => LoginUri(uri: controller.text.trim(), match: match);

  void dispose() => controller.dispose();
}

class _FieldDraft {
  final TextEditingController nameController;
  final TextEditingController valueController;
  CustomFieldType type;

  _FieldDraft({
    String name = '',
    String value = '',
    this.type = CustomFieldType.text,
  })  : nameController = TextEditingController(text: name),
        valueController = TextEditingController(text: value);

  factory _FieldDraft.from(CustomField field) => _FieldDraft(
        name: field.name,
        value: field.value,
        type: field.type,
      );

  CustomField toField() => CustomField(
        name: nameController.text.trim(),
        value: valueController.text,
        type: type,
      );

  void dispose() {
    nameController.dispose();
    valueController.dispose();
  }
}

// ==================== LIGNES ====================

class _UriRow extends StatelessWidget {
  const _UriRow({
    required this.draft,
    required this.enabled,
    required this.onRemove,
    required this.onChanged,
  });

  final _UriDraft draft;
  final bool enabled;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return HairlineCard(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.controller,
                  enabled: enabled,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'https://exemple.com',
                    prefixIcon: Icon(Icons.link_rounded, size: 20),
                    isDense: true,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              IconButton(
                tooltip: 'Retirer',
                onPressed: enabled ? onRemove : null,
                icon: Icon(Icons.close_rounded, size: 18, color: c.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<UriMatchType>(
                value: draft.match,
                isDense: true,
                borderRadius: Radii.all(Radii.sm),
                dropdownColor: c.surfaceRaised,
                style: Theme.of(context).textTheme.bodySmall,
                items: [
                  for (final type in UriMatchType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text('Correspondance : ${type.label}'),
                    ),
                ],
                onChanged: enabled
                    ? (value) {
                        if (value != null) {
                          draft.match = value;
                          onChanged();
                        }
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.draft,
    required this.enabled,
    required this.onRemove,
    required this.onChanged,
  });

  final _FieldDraft draft;
  final bool enabled;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;

    return HairlineCard(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.nameController,
                  enabled: enabled,
                  decoration: const InputDecoration(
                    hintText: 'Nom du champ',
                    isDense: true,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: Gap.sm),
              IconButton(
                tooltip: 'Retirer',
                onPressed: enabled ? onRemove : null,
                icon: Icon(Icons.close_rounded, size: 18, color: c.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          if (draft.type == CustomFieldType.boolean)
            SwitchListTile(
              value: draft.valueController.text == 'true',
              onChanged: enabled
                  ? (v) {
                      draft.valueController.text = v ? 'true' : 'false';
                      onChanged();
                    }
                  : null,
              title: Text(
                draft.valueController.text == 'true' ? 'Oui' : 'Non',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              contentPadding: EdgeInsets.zero,
            )
          else
            TextField(
              controller: draft.valueController,
              enabled: enabled,
              obscureText: draft.type == CustomFieldType.hidden,
              style: draft.type == CustomFieldType.hidden
                  ? SecretText.of(context)
                  : null,
              decoration: const InputDecoration(
                hintText: 'Valeur',
                isDense: true,
              ),
              onChanged: (_) => onChanged(),
            ),
          const SizedBox(height: Gap.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<CustomFieldType>(
                value: draft.type,
                isDense: true,
                borderRadius: Radii.all(Radii.sm),
                dropdownColor: c.surfaceRaised,
                style: Theme.of(context).textTheme.bodySmall,
                items: [
                  for (final type in CustomFieldType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text('Type : ${type.label}'),
                    ),
                ],
                onChanged: enabled
                    ? (value) {
                        if (value != null) {
                          draft.type = value;
                          onChanged();
                        }
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre d'enregistrement fixée en bas. Un formulaire long ne doit pas obliger à
/// remonter tout en haut pour valider.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.busy,
    required this.enabled,
    required this.isNew,
    required this.onSave,
  });

  final bool busy;
  final bool enabled;
  final bool isNew;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.xl, Gap.md),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: (busy || !enabled) ? null : onSave,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_rounded, size: 18),
                label: Text(busy ? 'Chiffrement…' : (isNew ? 'Ajouter' : 'Enregistrer')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
