package com.tannou.password_manager

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * Activité principale.
 *
 * Elle porte `FLAG_SECURE`, qui interdit à Android de capturer le contenu de
 * cette fenêtre. Trois conséquences, et les trois sont voulues :
 *
 *  * la capture d'écran est refusée par le système — un mot de passe affiché ne
 *    peut pas finir dans la galerie, d'où il partirait en sauvegarde cloud ;
 *  * l'enregistrement d'écran et le partage d'écran ne montrent qu'un cadre
 *    noir, ce qui couvre le cas d'une application malveillante disposant de la
 *    projection média ;
 *  * l'aperçu dans le sélecteur de tâches est masqué, donc le coffre n'est plus
 *    lisible par-dessus l'épaule après un passage en arrière-plan.
 *
 * Le drapeau est posé sur toute l'activité plutôt qu'au cas par cas. Le faire
 * écran par écran supposerait de n'oublier aucun chemin — un détail d'élément,
 * une feuille de génération, une boîte de dialogue, l'écran de remplissage
 * automatique — et le premier oubli annulerait la protection sans prévenir.
 *
 * Le coût assumé : aucune capture d'écran n'est possible dans l'app, y compris
 * pour signaler un défaut. C'est le compromis retenu par les gestionnaires de
 * mots de passe qui posent ce drapeau.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Avant super.onCreate : la fenêtre doit être protégée dès sa première
        // image, sans quoi il existe une fenêtre de quelques millisecondes où
        // elle est capturable.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }
}
