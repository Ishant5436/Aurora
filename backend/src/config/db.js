const mongoose = require('mongoose');

async function connectDb(uri) {
  mongoose.connection.on('error', (err) => console.error('[mongo] connection error:', err.message));
  await mongoose.connect(uri, { serverSelectionTimeoutMS: 10_000 });
  return mongoose.connection;
}

// Builds every declared index (unique emails, device ids, ...) before we serve
// traffic, so uniqueness is enforced from the first request.
async function initModels() {
  await Promise.all(Object.values(mongoose.models).map((m) => m.init()));
}

async function disconnectDb() {
  await mongoose.disconnect();
}

module.exports = { connectDb, initModels, disconnectDb };
