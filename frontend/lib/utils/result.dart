/// Simple success/failure wrapper so repositories return outcomes instead
/// of throwing across layer boundaries. Cubits pattern-match on this rather
/// than wrapping every repository call in try/catch.
sealed class Result<T> {
  const Result();

  factory Result.ok(T value) = Ok<T>;
  factory Result.err(String message) = Err<T>;

  R when<R>({
    required R Function(T value) ok,
    required R Function(String message) err,
  }) {
    final self = this;
    if (self is Ok<T>) return ok(self.value);
    if (self is Err<T>) return err(self.message);
    throw StateError('Unreachable');
  }
}

class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

class Err<T> extends Result<T> {
  const Err(this.message);
  final String message;
}
