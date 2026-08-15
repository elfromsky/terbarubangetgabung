import 'package:esh/app/app_dependencies.dart';
import 'package:esh/auth/device_claim.dart';
import 'package:esh/bloc/bloc_observer.dart';
import 'package:esh/bloc/history/history_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_event.dart';
import 'package:esh/firebase_options.dart';
import 'package:esh/routes/router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = AppBlocObserver();
  runApp(const FirebaseBootstrap());
}

enum _BootstrapState { loading, trusted, untrusted, error }

class FirebaseBootstrap extends StatefulWidget {
  const FirebaseBootstrap({super.key});

  @override
  State<FirebaseBootstrap> createState() => _FirebaseBootstrapState();
}

class _FirebaseBootstrapState extends State<FirebaseBootstrap>
    with WidgetsBindingObserver {
  _BootstrapState _state = _BootstrapState.loading;
  String? _uid;
  bool _revalidating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _revalidating) {
      return;
    }
    if (_state == _BootstrapState.loading) {
      return;
    }
    _revalidateTrust();
  }

  /// Ensures Firebase is initialized and a (possibly anonymous) user exists,
  /// then returns the ID-token claims.
  ///
  /// Returns `null` only for the bootstrap offline shell (a network failure
  /// captured when a force refresh was not requested). On a force refresh the
  /// same failure is rethrown so callers can reject the outcome safely.
  Future<Map<String, dynamic>?> _loadClaims({
    required bool forceClaimRefresh,
  }) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }

    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Firebase sign-in did not produce a user.');
    }

    try {
      final token = await user.getIdTokenResult(forceClaimRefresh);
      return token.claims;
    } on FirebaseAuthException catch (error) {
      if (!forceClaimRefresh && error.code == 'network-request-failed') {
        // Server-side rules remain the authority. Cached installations may
        // open the offline shell, but monitoring and control stay unavailable.
        return null;
      }
      rethrow;
    }
  }

  Future<void> _bootstrap() async {
    try {
      final claims = await _loadClaims(forceClaimRefresh: false);
      if (!mounted) {
        return;
      }
      // A null here means the offline shell: no server verdict is available,
      // which historically grants the shell but leaves data/control disabled.
      if (claims == null) {
        setState(() => _state = _BootstrapState.trusted);
        return;
      }
      final verdict = revalidateTrust(claims)!;
      setState(() {
        _state = verdict == DeviceTrust.trusted
            ? _BootstrapState.trusted
            : _BootstrapState.untrusted;
        _uid = FirebaseAuth.instance.currentUser?.uid;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _state = _BootstrapState.error);
    }
  }

  Future<void> _revalidateTrust() async {
    _revalidating = true;
    try {
      final claims = await _loadClaims(forceClaimRefresh: true);
      final verdict = revalidateTrust(claims);
      if (!mounted) {
        return;
      }
      if (verdict == DeviceTrust.untrusted &&
          _state != _BootstrapState.untrusted) {
        setState(() {
          _state = _BootstrapState.untrusted;
          _uid = FirebaseAuth.instance.currentUser?.uid;
        });
      } else if (verdict == DeviceTrust.trusted &&
          _state != _BootstrapState.trusted) {
        setState(() => _state = _BootstrapState.trusted);
      }
      // A null verdict (transient network failure) leaves the current state
      // untouched, avoiding an error bounce for a trusted device.
    } catch (_) {
      // Transient failure during resume re-validation: keep current state.
    } finally {
      _revalidating = false;
    }
  }

  Future<void> _retry() async {
    setState(() => _state = _BootstrapState.loading);
    await _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _BootstrapState.loading:
        return const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      case _BootstrapState.trusted:
        return EshApp(dependencies: AppDependencies.firebase());
      case _BootstrapState.untrusted:
        return _buildUntrustedApp();
      case _BootstrapState.error:
        return _buildErrorApp();
    }
  }

  Widget _buildUntrustedApp() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phonelink_lock, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Perangkat belum terdaftar',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Setelah administrator mendaftarkan perangkat ini, kembali '
                  'ke aplikasi untuk memeriksa ulang.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Jika status belum berubah, ketuk "Coba lagi".',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'ID perangkat:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SelectableText(_uid ?? '', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _retry,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorApp() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Firebase gagal diinisialisasi',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _retry,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EshApp extends StatelessWidget {
  final AppDependencies dependencies;

  const EshApp({super.key, required this.dependencies});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<MonitoringBloc>(
          create: (context) =>
              dependencies.createMonitoringBloc()..add(StartMonitoring()),
        ),
        BlocProvider<HistoryBloc>(
          create: (context) => dependencies.createHistoryBloc(),
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Monel Monitoring App',
        routerConfig: createRouter(
          estimateEnergyCost: dependencies.estimateEnergyCost,
          estimateEmission: dependencies.estimateEmission,
        ),
      ),
    );
  }
}
