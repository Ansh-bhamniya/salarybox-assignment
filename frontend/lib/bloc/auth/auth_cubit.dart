import 'package:flutter_bloc/flutter_bloc.dart';
import '../../utils/http/api_exception.dart';
import '../../services/auth_service.dart';
import './auth_state.dart';

/// App-wide session state. Created once in [app.dart] and provided above
/// the router, since the router's redirect guard needs to read it and
/// login/logout need to be reachable from anywhere.
class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._service) : super(const AuthState.unknown()) {
    _restore();
  }

  final AuthService _service;

  Future<void> _restore() async {
    final session = await _service.restoreSession();
    emit(session == null ? const AuthState.unauthenticated() : AuthState.authenticated(session));
  }

  Future<void> login({required String username, required String password}) async {
    emit(const AuthState(status: AuthStatus.authenticating));
    try {
      final session = await _service.login(username: username, password: password);
      emit(AuthState.authenticated(session));
    } on ApiException catch (e) {
      emit(AuthState.unauthenticated(errorMessage: e.message));
    }
  }

  Future<void> logout() async {
    await _service.logout();
    emit(const AuthState.unauthenticated());
  }
}
