/// Read-only school-year fee ledger. All money in integer minor units.
int _m(Object? v){
 if(v is int)return v;
 if(v is num&&v==v.roundToDouble())return v.toInt();
 if(v is String)return int.parse(v);
 throw const FormatException('Invalid money value');
}
List<Map<String,dynamic>> _rows(Object? value){
 if(value is! List)throw const FormatException('Invalid fee rows');
 return List.unmodifiable([
   for(final x in value)Map<String,dynamic>.from(x as Map),
 ]);
}
String _csv(Object? v)=>'"'+(v??'').toString().replaceAll('"','""')+'"';

class FeeLedgerTotals {
 const FeeLedgerTotals({required this.gross,required this.discount,
   required this.net,required this.paid,required this.outstanding,
   required this.count});
 final int gross,discount,net,paid,outstanding,count;
 factory FeeLedgerTotals.fromJson(Map<String,dynamic> x){
   final t=FeeLedgerTotals(
     gross:_m(x['gross_minor']),discount:_m(x['discount_minor']),
     net:_m(x['net_minor']),paid:_m(x['paid_minor']),
     outstanding:_m(x['outstanding_minor']),count:_m(x['charge_count']));
   if(t.gross<0||t.discount<0||t.paid<0||t.net<0||
       t.outstanding<0||t.count<0||t.gross-t.discount!=t.net||
       t.net-t.paid!=t.outstanding){
     throw const FormatException('Unbalanced fee totals');
   }
   return t;
 }
}
class FeeLedgerGroup {
 const FeeLedgerGroup(this.label,this.totals,{this.id,this.frequency});
 final String label;
 final FeeLedgerTotals totals;
 final String? id,frequency;
 factory FeeLedgerGroup.month(Map<String,dynamic> x)=>
   FeeLedgerGroup(x['month'].toString(),FeeLedgerTotals.fromJson(x));
 factory FeeLedgerGroup.category(Map<String,dynamic> x)=>
   FeeLedgerGroup(x['category'] as String,FeeLedgerTotals.fromJson(x),
     id:x['category_id'] as String,frequency:x['frequency'] as String);
}
class FeeLedgerChargeDetail {
 const FeeLedgerChargeDetail({required this.id,required this.category,
   required this.categoryId,required this.frequency,required this.month,
   required this.dueOn,required this.source,required this.description,
   required this.postedAt,required this.totals});
 final String id,category,categoryId,frequency,month,dueOn,source;
 final String description,postedAt;
 final FeeLedgerTotals totals;
 factory FeeLedgerChargeDetail.fromJson(Map<String,dynamic> x)=>
   FeeLedgerChargeDetail(
     id:x['id'] as String,category:x['category'] as String,
     categoryId:x['category_id'] as String,
     frequency:x['frequency'] as String,
     month:x['month'].toString(),dueOn:x['due_on'].toString(),
     source:x['source_kind'] as String,
     description:x['description'] as String? ?? '',
     postedAt:x['posted_at'].toString(),
     totals:FeeLedgerTotals.fromJson({...x,'charge_count':1}));
}
class FeeLedgerAllocationDetail{
 const FeeLedgerAllocationDetail({required this.id,required this.chargeId,
   required this.receiptId,required this.receiptNo,required this.category,
   required this.month,required this.amount,required this.method,
   required this.issuedAt});
 final String id,chargeId,receiptId,receiptNo,category,month,method,issuedAt;
 final int amount;
 factory FeeLedgerAllocationDetail.fromJson(Map<String,dynamic> x)=>
   FeeLedgerAllocationDetail(
     id:x['id'] as String,chargeId:x['charge_id'] as String,
     receiptId:x['receipt_id'] as String,
     receiptNo:x['receipt_no'] as String,
     category:x['category'] as String,month:x['month'].toString(),
     amount:_m(x['amount_minor']),method:x['payment_method'] as String,
     issuedAt:x['issued_at'].toString());
}
class FeeLedgerReceiptDetail{
 const FeeLedgerReceiptDetail({required this.id,required this.number,
   required this.total,required this.yearAllocated,required this.method,
   required this.issuedAt,this.bankReference});
 final String id,number,method,issuedAt;
 final String? bankReference;
 final int total,yearAllocated;
 factory FeeLedgerReceiptDetail.fromJson(Map<String,dynamic> x)=>
   FeeLedgerReceiptDetail(
     id:x['id'] as String,number:x['number'] as String,
     total:_m(x['receipt_total_minor']),
     yearAllocated:_m(x['allocated_to_year_minor']),
     method:x['method'] as String,issuedAt:x['issued_at'].toString(),
     bankReference:x['bank_reference'] as String?);
}
class FeeDetailedStudentLedger {
 const FeeDetailedStudentLedger({required this.schoolId,
   required this.campusId,required this.yearId,required this.studentId,
   required this.schoolName,required this.yearLabel,required this.studentName,
   required this.registration,required this.className,required this.currency,
   required this.totals,required this.months,required this.categories,
   required this.charges,required this.receipts,required this.allocations,
   this.sectionName});
 final String schoolId,campusId,yearId,studentId;
 final String schoolName,yearLabel,studentName,registration,className,currency;
 final String? sectionName;
 final FeeLedgerTotals totals;
 final List<FeeLedgerGroup> months,categories;
 final List<FeeLedgerChargeDetail> charges;
 final List<FeeLedgerReceiptDetail> receipts;
 final List<FeeLedgerAllocationDetail> allocations;
 factory FeeDetailedStudentLedger.fromJson(Map<String,dynamic> x){
   final data=FeeDetailedStudentLedger(
     schoolId:x['school_id'] as String,campusId:x['campus_id'] as String,
     yearId:x['year_id'] as String,studentId:x['student_id'] as String,
     schoolName:x['school_name'] as String,yearLabel:x['year_label'] as String,
     studentName:x['student_name'] as String,
     registration:x['registration'] as String,
     className:x['class_name'] as String,
     sectionName:x['section_name'] as String?,
     currency:x['currency'] as String,
     totals:FeeLedgerTotals.fromJson(Map<String,dynamic>.from(x['totals'] as Map)),
     months:List.unmodifiable([
       for(final r in _rows(x['months']))FeeLedgerGroup.month(r)]),
     categories:List.unmodifiable([
       for(final r in _rows(x['categories']))FeeLedgerGroup.category(r)]),
     charges:List.unmodifiable([
       for(final r in _rows(x['charges']))FeeLedgerChargeDetail.fromJson(r)]),
     receipts:List.unmodifiable([
       for(final r in _rows(x['receipts']))FeeLedgerReceiptDetail.fromJson(r)]),
     allocations:List.unmodifiable([
       for(final r in _rows(x['allocations']))
         FeeLedgerAllocationDetail.fromJson(r)]),
   );
   data.validate();return data;
 }
 void validate(){
   final c={for(final row in charges)row.id:row};
   final r={for(final row in receipts)row.id:row};
   if(c.length!=charges.length||r.length!=receipts.length){
     throw const FormatException('Duplicate fee record');
   }
   void check(FeeLedgerTotals all,Iterable<FeeLedgerTotals> rows){
     final data=rows.toList();
     int sum(int Function(FeeLedgerTotals) f)=>
       data.fold<int>(0,(n,v)=>n+f(v));
     if(sum((v)=>v.gross)!=all.gross||
       sum((v)=>v.discount)!=all.discount||
       sum((v)=>v.net)!=all.net||
       sum((v)=>v.paid)!=all.paid||
       sum((v)=>v.outstanding)!=all.outstanding||
       sum((v)=>v.count)!=all.count){
       throw const FormatException('Fee ledger does not reconcile');
     }
   }
   check(totals,charges.map((x)=>x.totals));
   check(totals,categories.map((x)=>x.totals));
   check(totals,months.map((x)=>x.totals));
   final byCharge=<String,int>{};
   final byReceipt=<String,int>{};
   for(final a in allocations){
     if(a.amount<=0||!c.containsKey(a.chargeId)||!r.containsKey(a.receiptId)){
       throw const FormatException('Invalid receipt allocation');
     }
     byCharge.update(a.chargeId,(v)=>v+a.amount,ifAbsent:()=>a.amount);
     byReceipt.update(a.receiptId,(v)=>v+a.amount,ifAbsent:()=>a.amount);
   }
   for(final row in charges){
     if((byCharge[row.id]??0)!=row.totals.paid){
       throw const FormatException('Charge payments do not reconcile');
     }
   }
   for(final row in receipts){
     if(row.total<=0||row.yearAllocated>row.total||
       row.yearAllocated!=(byReceipt[row.id]??0)){
       throw const FormatException('Receipt totals do not reconcile');
     }
   }
 }
 String chargesCsv(){
   final lines=<String>[
     'Student,Admission,Class,Category,Frequency,Month,Due,Source,Description,'
     'Charge ID,Gross Minor,Discount Minor,Billed Minor,Paid Minor,Due Minor'];
   for(final x in charges){
     lines.add([
       studentName,registration,className,x.category,x.frequency,x.month,
       x.dueOn,x.source,x.description,x.id,x.totals.gross,x.totals.discount,
       x.totals.net,x.totals.paid,x.totals.outstanding,
     ].map(_csv).join(','));
   }
   return lines.join('\r\n')+'\r\n';
 }
}
