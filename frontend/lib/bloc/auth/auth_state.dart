import 'package:equatable/equatable.dart';
import '../../models/session.dart';

enum AuthStatus { unknown, authenticating, authenticated, unauthenticated }

class AuthState extends Equatable {
  const AuthState({required this.status, this.session, this.errorMessage});

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.unauthenticated({String? errorMessage})
    : this(status: AuthStatus.unauthenticated, errorMessage: errorMessage);
  const AuthState.authenticated(Session session) : this(status: AuthStatus.authenticated, session: session);

  final AuthStatus status;
  final Session? session;
  final String? errorMessage;

  @override
  List<Object?> get props => [status, session?.token, errorMessage];
}
