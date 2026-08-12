const config = require('./src/config');
const { createApp } = require('./src/app');

const { app, store } = createApp(config);

// Ménage des sessions périmées : au démarrage puis une fois par jour.
store.deleteExpiredSessions();
const sweeper = setInterval(() => store.deleteExpiredSessions(), 86400_000);
sweeper.unref();

const server = app.listen(config.port, config.host, () => {
  const k = config.defaultKdf;
  console.log(`Coffort API v2 sur http://${config.host}:${config.port}`);
  console.log(`  base           : ${config.dbPath}`);
  console.log(`  inscriptions   : ${config.registration.mode}`);
  console.log(`  KDF par défaut : ${k.type} m=${k.memory} t=${k.iterations} p=${k.parallelism}`);
  if (config.registration.token) console.log('  jeton d’inscription requis');
});

function shutdown(signal) {
  console.log(`\n${signal} reçu, arrêt.`);
  server.close(() => {
    store.close();
    process.exit(0);
  });
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
