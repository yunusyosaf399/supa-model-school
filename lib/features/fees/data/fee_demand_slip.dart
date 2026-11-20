import 'fee_payment_repository.dart';

/// Read-only demand notices built from already-posted campus/year fee charges.
/// They do not create an invoice, receipt, or payment.
class FeeDemandLine {
  const FeeDemandLine({
    required this.chargeId,required this.category,required this.month,
    required this.dueOn,required this.billedMinor,required this.paidMinor,
    required this.dueMinor,required this.arrears,
  });
  final String chargeId,category,month,dueOn;
  final int billedMinor,paidMinor,dueMinor;
  final bool arrears;
}

class FeeDemandStudent {
  const FeeDemandStudent({
    required this.id,required this.name,required this.registration,
    required this.className,required this.sectionName,
    required this.lines,required this.currentDueMinor,
    required this.arrearsDueMinor,
  });
  final String id,name,registration,className;
  final String? sectionName;
  final List<FeeDemandLine> lines;
  final int currentDueMinor,arrearsDueMinor;
  int get totalDueMinor=>currentDueMinor+arrearsDueMinor;
}

class FeeDemandBatch {
  const FeeDemandBatch({
    required this.schoolId,required this.campusId,required this.yearId,
    required this.yearLabel,required this.currency,required this.month,
    required this.classId,required this.className,
    required this.students,required this.includeArrears,
    required this.generatedAtUtc,this.sectionName,
  });

  final String schoolId,campusId,yearId,yearLabel,currency;
  final String month,classId,className;
  final String? sectionName;
  final bool includeArrears;
  final DateTime generatedAtUtc;
  final List<FeeDemandStudent> students;

  int get currentDueMinor=>students.fold<int>(
    0,(sum,s)=>sum+s.currentDueMinor);
  int get arrearsDueMinor=>students.fold<int>(
    0,(sum,s)=>sum+s.arrearsDueMinor);
  int get totalDueMinor=>currentDueMinor+arrearsDueMinor;

  static FeeDemandBatch build({
    required FeePaymentWorkspace workspace,
    required String month,required String classId,
    String? sectionId,bool includeArrears=true,
    DateTime? generatedAtUtc,
  }){
    if(!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month)){
      throw const FormatException('Select a valid billing month (YYYY-MM)');
    }
    if(classId.isEmpty||!workspace.students.any((s)=>s.classId==classId)){
      throw const FormatException('Choose an existing class to print');
    }
    if(sectionId!=null&&!workspace.students.any(
      (s)=>s.classId==classId&&s.sectionId==sectionId)){
      throw const FormatException('Section is outside the selected class');
    }
    final students=workspace.students.where((s)=>
      s.classId==classId&&(sectionId==null||s.sectionId==sectionId)).toList()
      ..sort((a,b){
        final c=a.registration.compareTo(b.registration);
        return c!=0?c:a.name.compareTo(b.name);
      });
    if(students.map((s)=>s.id).toSet().length!=students.length){
      throw const FormatException('Duplicate student in fee workspace');
    }
    final output=<FeeDemandStudent>[];
    for(final s in students){
      final rows=<FeeDemandLine>[];
      final seen=<String>{};
      for(final c in s.charges){
        if(!seen.add(c.id)){
          throw const FormatException('Duplicate posted charge');
        }
        if(c.month.length<7||
          !RegExp(r'^\d{4}-(0[1-9]|1[0-2])').hasMatch(c.month)||
          c.netMinor<0||c.paidMinor<0||c.outstandingMinor<0||
          c.netMinor-c.paidMinor!=c.outstandingMinor){
          throw const FormatException('Fee balance does not reconcile');
        }
        final billMonth=c.month.substring(0,7);
        if(billMonth>month||c.outstandingMinor==0)continue;
        if(billMonth<month&&!includeArrears)continue;
        rows.add(FeeDemandLine(
          chargeId:c.id,category:c.categoryName,month:billMonth,
          dueOn:c.dueOn,billedMinor:c.netMinor,paidMinor:c.paidMinor,
          dueMinor:c.outstandingMinor,arrears:billMonth<month));
      }
      if(rows.isEmpty)continue;
      rows.sort((a,b){
        final date=a.month.compareTo(b.month);
        if(date!=0)return date;
        final due=a.dueOn.compareTo(b.dueOn);
        return due!=0?due:a.category.compareTo(b.category);
      });
      final current=rows.where((r)=>!r.arrears)
        .fold<int>(0,(sum,r)=>sum+r.dueMinor);
      final older=rows.where((r)=>r.arrears)
        .fold<int>(0,(sum,r)=>sum+r.dueMinor);
      output.add(FeeDemandStudent(
        id:s.id,name:s.name,registration:s.registration,
        className:s.className,sectionName:s.sectionName,
        lines:List.unmodifiable(rows),currentDueMinor:current,
        arrearsDueMinor:older));
    }
    return FeeDemandBatch(
      schoolId:workspace.schoolId,campusId:workspace.campusId,
      yearId:workspace.yearId,yearLabel:workspace.yearLabel,
      currency:workspace.currency,month:month,classId:classId,
      className:students.isEmpty?'':students.first.className,
      sectionName:sectionId==null?null:
        students.firstWhere((s)=>s.sectionId==sectionId).sectionName,
      students:List.unmodifiable(output),includeArrears:includeArrears,
      generatedAtUtc:(generatedAtUtc??DateTime.now()).toUtc());
  }
}
