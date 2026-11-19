import 'fee_detailed_statement.dart';

/// Read-only proof of a posted receipt. Built solely from the server's
/// reconciled fee ledger; this class NEVER creates a payment or receipt.
class FeeReceiptSlipLine {
  const FeeReceiptSlipLine({required this.category,required this.month,
    required this.amountMinor,required this.chargeId});
  final String category,month,chargeId;
  final int amountMinor;
}

class FeeReceiptSlip {
  const FeeReceiptSlip({
    required this.schoolName,required this.yearLabel,required this.currency,
    required this.studentName,required this.registration,
    required this.className,required this.receiptId,required this.receiptNo,
    required this.method,required this.issuedAt,required this.amountMinor,
    required this.lines,required this.categoryTotals,
    required this.priorReceipts,this.bankReference,this.sectionName,
  });

  final String schoolName,yearLabel,currency,studentName,registration,className;
  final String receiptId,receiptNo,method,issuedAt;
  final String? sectionName,bankReference;
  final int amountMinor;
  final List<FeeReceiptSlipLine> lines;
  final Map<String,int> categoryTotals;
  final List<FeeLedgerReceiptDetail> priorReceipts;

  factory FeeReceiptSlip.fromLedger(
      FeeDetailedStudentLedger ledger,String receiptId){
    ledger.validate();
    final receipt=ledger.receipts.where((r)=>r.id==receiptId).toList();
    if(receipt.length!=1) {
      throw StateError('This posted receipt is not in the selected student year');
    }
    final current=receipt.single;
    // A receipt can theoretically allocate to two years. The DB36 ledger
    // intentionally returns only the selected year. Reject rather than
    // printing an official receipt with missing category allocations.
    if(current.total<=0||current.yearAllocated!=current.total){
      throw StateError('This receipt spans other academic years; '
        'a complete receipt breakdown is required before printing');
    }
    final entries=ledger.allocations.where((a)=>a.receiptId==receiptId).toList()
      ..sort((a,b){
        final c=a.month.compareTo(b.month);
        return c!=0?c:a.category.compareTo(b.category);
      });
    if(entries.isEmpty || entries.any((a)=>a.amount<=0)){
      throw const FormatException('Receipt is missing posted allocations');
    }
    final totals=<String,int>{};
    for(final a in entries){
      totals.update(a.category,(v)=>v+a.amount,ifAbsent:()=>a.amount);
    }
    final amount=entries.fold<int>(0,(v,a)=>v+a.amount);
    if(amount!=current.total) {
      throw const FormatException('Receipt allocations do not match payment');
    }
    final before=ledger.receipts.where((r)=>r.id!=receiptId &&
       r.issuedAt.compareTo(current.issuedAt)<=0).toList()
       ..sort((a,b)=>b.issuedAt.compareTo(a.issuedAt));
    return FeeReceiptSlip(
      schoolName:ledger.schoolName,yearLabel:ledger.yearLabel,
      currency:ledger.currency,studentName:ledger.studentName,
      registration:ledger.registration,className:ledger.className,
      sectionName:ledger.sectionName,receiptId:current.id,
      receiptNo:current.number,method:current.method,
      issuedAt:current.issuedAt,bankReference:current.bankReference,
      amountMinor:current.total,
      lines:List.unmodifiable([
        for(final a in entries)FeeReceiptSlipLine(
          category:a.category,month:a.month,
          amountMinor:a.amount,chargeId:a.chargeId)]),
      categoryTotals:Map.unmodifiable(totals),
      priorReceipts:List.unmodifiable(before.take(5)),
    );
  }
}
