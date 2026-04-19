import 'dart:io';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/vessel_inspection_screen.dart';
import 'screens/questionnaire_screen.dart';
import 'screens/opo_survey_screen.dart';
import 'screens/sync_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/equipment_list_screen.dart';
import 'screens/assignments_screen.dart';
import 'screens/opo_list_screen.dart';
import 'screens/add_ndt_method_screen.dart';
import 'screens/verification_equipment_selection_screen.dart';
import 'screens/thickness_measurement_screen.dart';
import 'screens/image_annotation_screen.dart';
import 'screens/weld_defect_annotation_screen.dart';
import 'screens/drawing_template_picker_screen.dart';
import 'screens/drawing_annotation_screen.dart';
import 'models/equipment.dart';
import 'models/questionnaire.dart';
import 'models/vessel_checklist.dart';
import 'models/drawing_template.dart';

final _authService = AuthService();

final appRouter = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) async {
    final isLoggedIn = await _authService.isAuthenticated();
    final isLoginPage = state.matchedLocation == '/login';

    if (!isLoggedIn && !isLoginPage) return '/login';
    if (isLoggedIn && isLoginPage) return '/dashboard';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/inspection',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return VesselInspectionScreen(
          equipment: extra['equipment'] as Equipment,
          assignmentId: extra['assignmentId'] as String?,
          existingInspectionId: extra['existingInspectionId'] as String?,
          inspectionType: extra['inspectionType'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/questionnaire',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return QuestionnaireScreen(
          equipment: extra['equipment'] as Equipment,
          existingQuestionnaire:
              extra['existingQuestionnaire'] as Questionnaire?,
        );
      },
    ),
    GoRoute(
      path: '/opo-survey',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return OpoSurveyScreen(
          opoId: extra['opoId'] as String,
          opoName: extra['opoName'] as String,
        );
      },
    ),
    GoRoute(
      path: '/sync',
      builder: (context, state) => const SyncScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/add-ndt-method',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return AddNDTMethodScreen(
          questionnaireId: extra['questionnaireId'] as String,
          existingMethod: extra['existingMethod'] as NDTMethod?,
        );
      },
    ),
    GoRoute(
      path: '/verification-equipment',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return VerificationEquipmentSelectionScreen(
          preselectedIds: extra['preselectedIds'] as List<String>?,
        );
      },
    ),
    GoRoute(
      path: '/thickness-measurement',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ThicknessMeasurementScreen(
          schemeImage: extra['schemeImage'] as File?,
          existingMeasurements:
              extra['existingMeasurements'] as List<ThicknessMeasurement>?,
          equipment: extra['equipment'] as Equipment?,
        );
      },
    ),
    GoRoute(
      path: '/image-annotation',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ImageAnnotationScreen(
          title: extra['title'] as String?,
          initialImage: extra['initialImage'] as File?,
        );
      },
    ),
    GoRoute(
      path: '/weld-defect-annotation',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return WeldDefectAnnotationScreen(
          initialImage: extra['initialImage'] as File?,
        );
      },
    ),
    GoRoute(
      path: '/drawing-template-picker',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return DrawingTemplatePickerScreen(
          equipment: extra['equipment'] as Equipment,
          title: extra['title'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/drawing-annotation',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return DrawingAnnotationScreen(
          template: extra['template'] as DrawingTemplate,
          equipmentName: extra['equipmentName'] as String?,
          existingMeasurements: extra['existingMeasurements'] as Map<String, double>?,
        );
      },
    ),
  ],
);
