# Règles R8 pour le build release.
#
# flutter_autofill_service dépend de kotlin-logging et tinylog, qui référencent
# des moteurs de journalisation de bureau — Logback, JNDI, JMX, l'API de gestion
# de la JVM. Aucun n'existe sur Android, et aucun n'est atteint à l'exécution :
# ces bibliothèques choisissent leur implémentation dynamiquement et retombent
# sur celle d'Android.
#
# R8 refuse néanmoins de terminer tant qu'il voit des références non résolues.
# `-dontwarn` lui dit que l'absence est attendue. Il ne conserve rien de plus et
# ne désactive aucune optimisation — c'est uniquement la mise en échec sur
# avertissement qui est levée.
#
# Liste produite par R8 lui-même, dans
# build/app/outputs/mapping/release/missing_rules.txt.

# ── Logback, moteur de journalisation absent sur Android ──
-dontwarn ch.qos.logback.classic.Level
-dontwarn ch.qos.logback.classic.Logger
-dontwarn ch.qos.logback.classic.LoggerContext
-dontwarn ch.qos.logback.classic.spi.ILoggingEvent
-dontwarn ch.qos.logback.classic.spi.LoggingEvent

# ── API internes de la JVM de bureau, référencées par tinylog ──
-dontwarn java.lang.ProcessHandle
-dontwarn java.lang.management.ManagementFactory
-dontwarn java.lang.management.RuntimeMXBean
-dontwarn sun.reflect.Reflection

# ── JNDI, utilisé par tinylog pour lire une configuration en environnement
#    applicatif Java. Sans objet ici. ──
-dontwarn javax.naming.InitialContext
-dontwarn javax.naming.NameNotFoundException
-dontwarn javax.naming.NamingException

# ── API Android privée, sondée par tinylog pour accélérer la lecture de pile.
#    Absente des SDK récents ; tinylog gère son absence. ──
-dontwarn dalvik.system.VMStack
