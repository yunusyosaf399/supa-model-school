import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/fee_setup_repository.dart';
import '../data/fee_payment_repository.dart';

class _BillLine {
 const _BillLine(this.student,this.charge);
 final FeePaymentStudent student;
 final FeePaymentCharge charge;
}
class _Totals {
 int billed=0,paid=0,outstanding=0,count=0;
 final Set<String> students=<String>{};
 void add(_BillLine line){
   billed+=line.charge.netMinor;paid+=line.charge.paidMinor;
   outstanding+=line.charge.outstandingMinor;
   count++;students.add(line.student.id);
 }
}
class FeeBillingReportsPage extends StatefulWidget {
 const FeeBillingReportsPage({super.key,required this.workspace});
 final FeePaymentWorkspace workspace;
 @override State<FeeBillingReportsPage> createState()=>_FeeBillingReportsPageState();
}
class _FeeBillingReportsPageState extends State<FeeBillingReportsPage>{
 String? classId,sectionId,categoryId,month;
 bool printing=false;
 String cash(int v)=>widget.workspace.currency+' '+FeeMoney.showMinor(v);
 List<_BillLine> selectedLines(){
   final result=<_BillLine>[];
   for(final s in widget.workspace.students){
     if(classId!=null&&s.classId!=classId)continue;
     if(sectionId!=null&&s.sectionId!=sectionId)continue;
     for(final c in s.charges){
       if(categoryId!=null&&c.categoryId!=categoryId)continue;
       if(month!=null&&!c.month.startsWith(month!))continue;
       result.add(_BillLine(s,c));
     }
   }
   return result;
 }
 Map<String,_Totals> group(List<_BillLine> lines,
   String Function(_BillLine) selector){
   final rows=<String,_Totals>{};
   for(final line in lines){
     (rows[selector(line)]??= _Totals()).add(line);
   }
   return Map.fromEntries(rows.entries.toList()
     ..sort((a,b)=>a.key.compareTo(b.key)));
 }
 String toCsv(List<_BillLine> lines){
   String q(Object? x)=>'"'+(x??'').toString().replaceAll('"','""')+'"';
   final rows=<String>[
     'Class,Section,Admission,Student,Category,Billing Month,Charge ID,'
     'Billed Minor,Paid Minor,Outstanding Minor',
   ];
   for(final l in lines){
     rows.add([
       l.student.className,l.student.sectionName,l.student.registration,
       l.student.name,l.charge.categoryName,l.charge.month,l.charge.id,
       l.charge.netMinor,l.charge.paidMinor,l.charge.outstandingMinor,
     ].map(q).join(','));
   }
   return rows.join('\r\n')+'\r\n';
 }

 Future<void> printReport(List<_BillLine> lines)async{
   if(printing)return;
   setState(()=>printing=true);
   try{
     final currency=widget.workspace.currency;
     String m(int x)=>FeeMoney.showMinor(x);
     final categories=group(lines,(l)=>l.charge.categoryName);
     final months=group(lines,(l)=>l.charge.month.substring(0,7));
     final classes=group(lines,(l)=>l.student.className);
     final totals=_Totals();
     for(final line in lines)totals.add(line);
     final doc=pw.Document(title:'School fee billing report',
       creator:'Supa Model School');
     pw.Widget table(List<String> head,List<List<String>> data)=>
       pw.TableHelper.fromTextArray(headers:head,
         data:data.isEmpty?[List.filled(head.length,'—')]:data,
         headerStyle:pw.TextStyle(fontSize:8,fontWeight:pw.FontWeight.bold),
         cellStyle:const pw.TextStyle(fontSize:7),
         cellPadding:const pw.EdgeInsets.all(4),
         headerDecoration:const pw.BoxDecoration(color:PdfColors.grey200),
         border:pw.TableBorder.all(color:PdfColors.grey300,width:0.4));
     pw.Widget heading(String value)=>pw.Padding(
       padding:const pw.EdgeInsets.only(top:12,bottom:5),
       child:pw.Text(value,style:pw.TextStyle(fontSize:11,
         fontWeight:pw.FontWeight.bold)));
     doc.addPage(pw.MultiPage(maxPages:400,
       margin:const pw.EdgeInsets.all(30),
       pageFormat:PdfPageFormat.a4,
       header:(ctx)=>pw.Column(
         crossAxisAlignment:pw.CrossAxisAlignment.start,
         children:[
           pw.Text('Fee Billing Summary - '+widget.workspace.yearLabel,
             style:pw.TextStyle(fontSize:14,fontWeight:pw.FontWeight.bold)),
           pw.Divider(),
         ]),
       footer:(ctx)=>pw.Text('Page '+ctx.pageNumber.toString()+' of '+
          ctx.pagesCount.toString(),
          style:const pw.TextStyle(fontSize:7)),
       build:(ctx)=>[
         pw.Text('Campus financial charges | '+currency+
           ' | '+lines.length.toString()+' posted charges'),
         pw.Text('Billed '+m(totals.billed)+' | Paid '+m(totals.paid)+
           ' | Outstanding '+m(totals.outstanding)),
         pw.Text('Payments are grouped by the month of the charge, '
           'not by the date of cash receipt.',
           style:const pw.TextStyle(fontSize:8)),
         heading('Category-wise billing'),
         table(['Category','Count','Billed','Paid','Outstanding'],[
           for(final e in categories.entries)[
             e.key,e.value.count.toString(),
             m(e.value.billed),m(e.value.paid),m(e.value.outstanding)],
         ]),
         heading('Month-wise billing'),
         table(['Month','Count','Billed','Paid','Outstanding'],[
           for(final e in months.entries)[
             e.key,e.value.count.toString(),
             m(e.value.billed),m(e.value.paid),m(e.value.outstanding)],
         ]),
         heading('Class-wise billing'),
         table(['Class','Students','Billed','Paid','Outstanding'],[
           for(final e in classes.entries)[
             e.key,e.value.students.length.toString(),
             m(e.value.billed),m(e.value.paid),m(e.value.outstanding)],
         ]),
         heading('Posted charge details'),
         table(['Class','Student','Category','Month','Billed','Paid','Due'],[
           for(final l in lines)[l.student.className,
             l.student.registration,l.charge.categoryName,
             l.charge.month.substring(0,7),
             m(l.charge.netMinor),m(l.charge.paidMinor),
             m(l.charge.outstandingMinor)],
         ]),
       ]));
     await Printing.layoutPdf(
       name:'Fee billing - '+widget.workspace.yearLabel,
       onLayout:(format)async=>doc.save());
   }catch(e){
     if(mounted)ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content:Text('Unable to print billing report: '+e.toString())));
   }finally{
     if(mounted)setState(()=>printing=false);
   }
 }

 @override Widget build(BuildContext context){
   final w=widget.workspace;
   final allClasses=<String,String>{
     for(final s in w.students)s.classId:s.className};
   final allSections=<String,String>{
     for(final s in w.students)
       if(s.sectionId!=null&&(classId==null||s.classId==classId))
         s.sectionId!:s.className+' · '+(s.sectionName??'Section')};
   final allMonths=<String>{
     for(final s in w.students)
       for(final c in s.charges)c.month.substring(0,7),
   }.toList()..sort();
   final lines=selectedLines();
   final summary=_Totals();for(final l in lines)summary.add(l);
   final byCat=group(lines,(l)=>l.charge.categoryName);
   final byMonth=group(lines,(l)=>l.charge.month.substring(0,7));
   final byClass=group(lines,(l)=>l.student.className);
   Widget box(String label,String value)=>Card.outlined(
     child:Padding(padding:const EdgeInsets.all(12),
       child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
         Text(label,style:Theme.of(context).textTheme.bodySmall),
         Text(value,style:Theme.of(context).textTheme.titleMedium),
       ])));
   Widget summaryRow(String name,_Totals t)=>ListTile(
     title:Text(name),
     subtitle:Text(t.count.toString()+' bills · '+
       t.students.length.toString()+' students\nBilled '+
       cash(t.billed)+' · Paid '+cash(t.paid)),
     trailing:Text('Due '+cash(t.outstanding)),
   );
   Widget select(String key,String label,String? value,
     List<DropdownMenuItem<String>> items,ValueChanged<String?> changed)=>
     SizedBox(width:210,child:DropdownButtonFormField<String>(
       key:Key(key),value:value??'all',isExpanded:true,
       decoration:InputDecoration(labelText:label,
         border:const OutlineInputBorder(),isDense:true),
       items:items,onChanged:changed));
   return Scaffold(
     appBar:AppBar(title:const Text('Fee Billing Reports')),
     body:ListView(key:const Key('fee-billing-reports-page'),
       padding:const EdgeInsets.all(16),children:[
       Text('Category, Class & Monthly Fee Reports',
         style:Theme.of(context).textTheme.titleLarge),
       Text('Academic Year: '+w.yearLabel+' · '+w.currency+
         ' · Current authorized campus'),
       const Text('Billed and paid figures reflect posted charges and '
         'receipt allocations. This is not a cash-collection-by-date report.'),
       const SizedBox(height:12),
       Wrap(spacing:8,runSpacing:8,children:[
         select('billing-report-class','Class',classId,[
           const DropdownMenuItem(value:'all',child:Text('All classes')),
           for(final e in allClasses.entries)
             DropdownMenuItem(value:e.key,child:Text(e.value)),
         ],(v)=>setState((){
           classId=v=='all'?null:v;sectionId=null;
         })),
         select('billing-report-section','Section',sectionId,[
           const DropdownMenuItem(value:'all',child:Text('All sections')),
           for(final e in allSections.entries)
             DropdownMenuItem(value:e.key,child:Text(e.value)),
         ],(v)=>setState(()=>sectionId=v=='all'?null:v)),
         select('billing-report-category','Category',categoryId,[
           const DropdownMenuItem(value:'all',child:Text('All categories')),
           for(final c in w.categories)
             DropdownMenuItem(value:c.id,child:Text(c.name,
               overflow:TextOverflow.ellipsis)),
         ],(v)=>setState(()=>categoryId=v=='all'?null:v)),
         select('billing-report-month','Billing month',month,[
           const DropdownMenuItem(value:'all',child:Text('All months')),
           for(final m in allMonths)
             DropdownMenuItem(value:m,child:Text(m)),
         ],(v)=>setState(()=>month=v=='all'?null:v)),
       ]),
       const SizedBox(height:12),
       Wrap(spacing:7,runSpacing:7,children:[
         OutlinedButton.icon(key:const Key('billing-report-csv'),
           onPressed:()=>Clipboard.setData(ClipboardData(text:toCsv(lines))),
           icon:const Icon(Icons.copy_outlined),
           label:const Text('Copy Detailed CSV')),
         FilledButton.icon(key:const Key('billing-report-print'),
           onPressed:printing?null:()=>printReport(lines),
           icon:const Icon(Icons.print_outlined),
           label:const Text('Print Billing Report')),
       ]),
       const SizedBox(height:10),
       Wrap(spacing:8,runSpacing:8,children:[
         box('Charges',summary.count.toString()),
         box('Students',summary.students.length.toString()),
         box('Billed',cash(summary.billed)),
         box('Paid',cash(summary.paid)),
         box('Outstanding',cash(summary.outstanding)),
       ]),
       const SizedBox(height:12),
       Text('Category Totals',style:Theme.of(context).textTheme.titleLarge),
       for(final e in byCat.entries)Card.outlined(child:summaryRow(e.key,e.value)),
       const SizedBox(height:12),
       Text('Monthly Totals',style:Theme.of(context).textTheme.titleLarge),
       for(final e in byMonth.entries)Card.outlined(child:summaryRow(e.key,e.value)),
       const SizedBox(height:12),
       Text('Class Totals',style:Theme.of(context).textTheme.titleLarge),
       for(final e in byClass.entries)Card.outlined(child:summaryRow(e.key,e.value)),
       if(lines.isEmpty)
         const Padding(padding:EdgeInsets.all(15),
           child:Text('No posted fees match these filters.')),
     ]),
   );
 }
}
