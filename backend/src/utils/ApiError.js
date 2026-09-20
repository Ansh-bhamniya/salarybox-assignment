export class ApiError extends Error {
  /** @param code optional machine-readable reason (e.g. 'not_enrolled') for clients that want to branch on it. */
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
