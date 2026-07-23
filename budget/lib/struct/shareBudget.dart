import 'dart:async';
import 'package:budget/database/tables.dart';

// Shared budgets removed - Firebase Firestore no longer supported

Future<bool> shareBudget(Budget? budgetToShare, context) async {
  // Shared budgets feature removed
  print("Shared budgets feature is no longer available");
  return false;
}

Future<void> syncPendingQueueOnServer() async {
  // Shared budgets sync removed
  return;
}

Future<void> getCloudBudgets() async {
  // Shared budgets feature removed
  return;
}

Future<bool> removedSharedFromBudget(Budget sharedBudget,
    {bool removeFromServer = true}) async {
  // Shared budgets feature removed
  return false;
}

Future<bool> leaveSharedBudget(Budget sharedBudget) async {
  // Shared budgets feature removed
  return false;
}

Future<bool> addMemberToBudget(
    String sharedKey, String member, Budget budget) async {
  // Shared budgets feature removed
  return false;
}

Future<bool> removeMemberFromBudget(
    String sharedKey, String member, Budget budget) async {
  // Shared budgets feature removed
  return false;
}

Future<dynamic> getMembersFromBudget(String sharedKey, Budget budget) async {
  // Shared budgets feature removed
  return null;
}

Future<bool> sendTransactionSet(Transaction transaction, Budget budget) async {
  // Shared budgets feature removed
  return false;
}

Future<bool> sendTransactionAdd(Transaction transaction, Budget budget) async {
  // Shared budgets feature removed
  return false;
}

Future<bool> sendTransactionDelete(
    Transaction transaction, Budget budget) async {
  // Shared budgets feature removed
  return false;
}

Future<bool> updateTransactionOnServerAfterChangingCategoryInformation(
    TransactionCategory category) async {
  // Shared budgets feature removed
  return false;
}

String getMemberNickname(String email) {
  return email;
}
