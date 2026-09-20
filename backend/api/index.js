// Vercel serverless entry point. Vercel invokes the exported Express app as a
// request handler, so server.js (app.listen) is only used for local dev.
import { app } from '../src/app.js';

export default app;
