import 'package:purchases_flutter/purchases_flutter.dart';

enum SubscriptionStatus {
  uninitialized,
  loading,
  inactive,
  active,
  purchasing,
  restoring,
  error,
}

class SubscriptionState {
  final SubscriptionStatus status;
  final bool isPro;
  final CustomerInfo? customerInfo;
  final Offerings? offerings;
  final String? errorMessage;
  final DateTime? expirationDate;

  const SubscriptionState({
    this.status = SubscriptionStatus.uninitialized,
    this.isPro = false,
    this.customerInfo,
    this.offerings,
    this.errorMessage,
    this.expirationDate,
  });

  bool get isLoading => status == SubscriptionStatus.loading;
  bool get isPurchasing => status == SubscriptionStatus.purchasing;
  bool get isRestoring => status == SubscriptionStatus.restoring;

  SubscriptionState copyWith({
    SubscriptionStatus? status,
    bool? isPro,
    CustomerInfo? customerInfo,
    Offerings? offerings,
    String? errorMessage,
    DateTime? expirationDate,
  }) {
    return SubscriptionState(
      status: status ?? this.status,
      isPro: isPro ?? this.isPro,
      customerInfo: customerInfo ?? this.customerInfo,
      offerings: offerings ?? this.offerings,
      errorMessage: errorMessage,
      expirationDate: expirationDate ?? this.expirationDate,
    );
  }
}
