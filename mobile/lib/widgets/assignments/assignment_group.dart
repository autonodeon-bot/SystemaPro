import '../../models/assignment.dart';

class AssignmentGroup {
  const AssignmentGroup({
    this.enterpriseName,
    this.branchName,
    this.workshopName,
    this.opoName,
    required this.assignments,
  });

  final String? enterpriseName;
  final String? branchName;
  final String? workshopName;
  final String? opoName;
  final List<Assignment> assignments;

  String get key {
    return '${enterpriseName ?? 'Без предприятия'}_${branchName ?? ''}_${workshopName ?? ''}_${opoName ?? ''}';
  }

  String get displayName {
    if (enterpriseName != null && enterpriseName!.isNotEmpty) {
      if (branchName != null && branchName!.isNotEmpty) {
        if (workshopName != null && workshopName!.isNotEmpty) {
          if (opoName != null && opoName!.isNotEmpty) {
            return '$enterpriseName → $branchName → $workshopName → $opoName';
          }
          return '$enterpriseName → $branchName → $workshopName';
        }
        return '$enterpriseName → $branchName';
      }
      return enterpriseName!;
    }
    if (branchName != null && branchName!.isNotEmpty) {
      if (workshopName != null && workshopName!.isNotEmpty) {
        if (opoName != null && opoName!.isNotEmpty) {
          return '[Филиал] $branchName → $workshopName → $opoName';
        }
        return '[Филиал] $branchName → $workshopName';
      }
      return '[Филиал] $branchName';
    }
    if (workshopName != null && workshopName!.isNotEmpty) {
      if (opoName != null && opoName!.isNotEmpty) {
        return '[Цех] $workshopName → $opoName';
      }
      return '[Цех] $workshopName';
    }
    if (opoName != null && opoName!.isNotEmpty) {
      return '[ОПО] $opoName';
    }
    return 'Без привязки';
  }
}
