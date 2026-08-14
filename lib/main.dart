import 'package:esh/app/app_dependencies.dart';
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

class UntrustedDeviceException implements Exception {
  final String uid;

  const UntrustedDeviceException(this.uid);
}

bool hasTrustedDeviceClaim(Map<String, dynamic>? claims) {
  return claims?['owner'] == true || claims?['controller'] == true;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = AppBlocObserver();
  runApp(const FirebaseBootstrap());
}

class FirebaseBootstrap extends StatefulWidget {
  const FirebaseBootstrap({super.key});

  @override
  State<FirebaseBootstrap> createState() => _FirebaseBootstrapState();
}

class _FirebaseBootstrapState extends State<FirebaseBootstrap> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initializeFirebase();
  }

  Future<void> _initializeFirebase({bool forceClaimRefresh = false}) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }

    final user = auth.currentUser!;
    IdTokenResult token;
    try {
      token = await user.getIdTokenResult(forceClaimRefresh);
    } on FirebaseAuthException catch (error) {
      if (!forceClaimRefresh && error.code == 'network-request-failed') {
        // Server-side rules remain the authority. Cached installations may
        // open the offline shell, but monitoring and control stay unavailable.
        return;
      }
      rethrow;
    }
    if (!hasTrustedDeviceClaim(token.claims)) {
      throw UntrustedDeviceException(user.uid);
    }
  }

  void _retry() {
    setState(() {
      _initialization = _initializeFirebase(forceClaimRefresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }

        if (snapshot.hasError) {
          debugPrint('Firebase initialization failed: ${snapshot.error}');
          final error = snapshot.error;
          final isUntrustedDevice = error is UntrustedDeviceException;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUntrustedDevice
                            ? Icons.phonelink_lock
                            : Icons.cloud_off,
                        size: 56,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isUntrustedDevice
                            ? 'Perangkat belum terdaftar'
                            : 'Firebase gagal diinisialisasi',
                        textAlign: TextAlign.center,
                      ),
                      if (isUntrustedDevice) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Daftarkan UID berikut sebagai owner, lalu coba lagi.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        SelectableText(error.uid, textAlign: TextAlign.center),
                      ],
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

        return EshApp(dependencies: AppDependencies.firebase());
      },
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
