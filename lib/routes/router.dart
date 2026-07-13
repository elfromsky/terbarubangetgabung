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

final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      name: Routes.monitoringScreen,
      pageBuilder: (context, state) =>
          buildTransitionPage(const MonitoringPage(), state),
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
