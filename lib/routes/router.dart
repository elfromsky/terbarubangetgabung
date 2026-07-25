import 'package:esh/features/monitoring/domain/usecases/estimate_emission_use_case.dart';
import 'package:esh/features/monitoring/domain/usecases/estimate_energy_cost_use_case.dart';
import 'package:esh/routes/router_name.dart';
import 'package:esh/screen/history.dart';
import 'package:esh/screen/monitoring.dart';
import 'package:esh/screen/control.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

CustomTransitionPage buildTransitionPage(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.1),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      );
    },
  );
}

GoRouter createRouter({
  required EstimateEnergyCostUseCase estimateEnergyCost,
  required EstimateEmissionUseCase estimateEmission,
}) {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        name: Routes.monitoringScreen,
        pageBuilder: (context, state) => buildTransitionPage(
          MonitoringPage(
            estimateEnergyCost: estimateEnergyCost,
            estimateEmission: estimateEmission,
          ),
          state,
        ),
      ),
      GoRoute(
        path: '/history',
        name: Routes.historyScreen,
        pageBuilder: (context, state) =>
            buildTransitionPage(const History(), state),
      ),
      GoRoute(
        path: '/control',
        name: Routes.controlScreen,
        pageBuilder: (context, state) =>
            buildTransitionPage(const ControlPage(), state),
      ),
    ],
  );
}
