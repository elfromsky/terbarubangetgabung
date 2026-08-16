import 'package:esh/app/app_dependencies.dart';
import 'package:esh/auth/auth_gate_controller.dart';
import 'package:esh/auth/firebase_claims.dart';
import 'package:esh/bloc/bloc_observer.dart';
import 'package:esh/bloc/history/history_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_bloc.dart';
import 'package:esh/bloc/monitoring/monitoring_event.dart';
import 'package:esh/routes/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = AppBlocObserver();

  final claims = FirebaseClaims();
  final controller = AuthGateController(
    loadClaims: claims.loadClaims,
    loadUid: claims.currentUid,
  );

  runApp(FirebaseBootstrap(controller: controller));
}

/// Authorization bootstrap gate.
///
/// Establishes the anonymous Firebase identity and verifies the `owner` claim
/// before (and only before) constructing the operational [EshApp]. Fail-closed:
/// loading, unprovisioned, and error states never reach the operational tree.
class FirebaseBootstrap extends StatefulWidget {
  const FirebaseBootstrap({
    super.key,
    required this.controller,
    this.trustedAppBuilder,
  });

  final AuthGateController controller;

  /// Injection seam for tests so the trusted state does not have to construct
  /// the Firebase-backed [EshApp].
  final Widget Function()? trustedAppBuilder;

  @override
  State<FirebaseBootstrap> createState() => _FirebaseBootstrapState();
}

class _FirebaseBootstrapState extends State<FirebaseBootstrap>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.revalidate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        switch (widget.controller.status) {
          case AuthGateStatus.loading:
            return const _LoadingApp();
          case AuthGateStatus.trusted:
            return _buildTrustedApp();
          case AuthGateStatus.unprovisioned:
            return _EnrollmentApp(controller: widget.controller);
          case AuthGateStatus.error:
            return _ErrorApp(onRetry: widget.controller.retry);
        }
      },
    );
  }

  Widget _buildTrustedApp() {
    final builder = widget.trustedAppBuilder;
    if (builder != null) {
      return builder();
    }
    return EshApp(dependencies: AppDependencies.firebase());
  }
}

class _LoadingApp extends StatelessWidget {
  const _LoadingApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

class _EnrollmentApp extends StatelessWidget {
  const _EnrollmentApp({required this.controller});

  final AuthGateController controller;

  @override
  Widget build(BuildContext context) {
    final uid = controller.uid;
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Perangkat ini belum mendapatkan akses.\n'
                  'Daftarkan UID Firebase berikut melalui proses provisioning.',
                  textAlign: TextAlign.center,
                ),
                if (uid != null) ...[
                  const SizedBox(height: 16),
                  const Text('ID perangkat:'),
                  SelectableText(
                    uid,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: controller.retry,
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

class _ErrorApp extends StatelessWidget {
  const _ErrorApp({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
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
                  onPressed: onRetry,
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
