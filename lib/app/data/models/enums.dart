enum TransactionKind { income, expense }

enum SavingsSource { manual, monthEnd, recurring }

/// What a recurring rule creates: a transaction, or a savings movement.
enum RecurringKind { income, expense, saving }
