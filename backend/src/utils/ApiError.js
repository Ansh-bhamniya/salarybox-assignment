export class ApiError extends Error {
  /**
   * @param code optional machine-readable reason (e.g. 'not_enrolled') for clients that want to branch on it.
   * @param details optional extra data for the client (e.g. which staff a face matched).
   */
  constructor(status, message, code, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}
