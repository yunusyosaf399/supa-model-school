import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/fee_receipt_slip.dart';
import '../data/fee_setup_repository.dart';

/// Read-only dual-copy PDF: each copy is its own page to prevent truncation.
class FeeReceiptSlipPdf {
  const FeeReceiptSlipPdf._();

  static String amount(int minor)=>FeeMoney.showMinor(minor);

  static String issued(String value){
    final d=DateTime.tryParse(value)?.toUtc();
    if(d==null)return value;
    String two(int v)=>v.toString().padLeft(2,'0');
    return d.year.toString()+'-'+two(d.month)+'-'+two(d.day)+' '
      +two(d.hour)+':'+two(d.minute)+' UTC';
  }

  static pw.Widget _heading(String value)=>pw.Padding(
    padding:const pw.EdgeInsets.only(top:13,bottom:6),
    child:pw.Text(value,style:pw.TextStyle(
      fontSize:10,fontWeight:pw.FontWeight.bold)));

  static pw.Widget _table(List<String> headers,List<List<String>> rows)=>
    pw.TableHelper.fromTextArray(
      headers:headers,
      data:rows.isEmpty?[List<String>.filled(headers.length,'—')]:rows,
      headerDecoration:const pw.BoxDecoration(color:PdfColors.grey200),
      headerStyle:pw.TextStyle(fontSize:9,fontWeight:pw.FontWeight.bold),
      cellStyle:const pw.TextStyle(fontSize:8),
      cellPadding:const pw.EdgeInsets.symmetric(vertical:5,horizontal:5),
      border:pw.TableBorder.all(color:PdfColors.grey400,width:0.5));

  static List<pw.Widget> _copy(FeeReceiptSlip s,String label){
    return [
      pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[
        pw.Text('OFFICIAL FEE COLLECTION RECEIPT',
          style:pw.TextStyle(fontSize:12,fontWeight:pw.FontWeight.bold)),
        pw.Text(label,style:pw.TextStyle(
          fontSize:10,fontWeight:pw.FontWeight.bold)),
      ]),
      pw.SizedBox(height:7),
      pw.Text(s.schoolName,style:pw.TextStyle(
        fontSize:17,fontWeight:pw.FontWeight.bold)),
      pw.Text('Academic Year: '+s.yearLabel,
        style:const pw.TextStyle(fontSize:9)),
      pw.Divider(),
      pw.SizedBox(height:8),
      _table(['Receipt Number','Issued At (UTC)','Payment Method'],[[
        s.receiptNo,issued(s.issuedAt),s.method.toUpperCase(),
      ]]),
      pw.SizedBox(height:10),
      _table(['Student','Admission / Registration','Class / Section'],[[
        s.studentName,s.registration,s.className+
          (s.sectionName==null?'':' / '+s.sectionName!),
      ]]),
      if(s.bankReference!=null&&s.bankReference!.isNotEmpty)
        pw.Padding(padding:const pw.EdgeInsets.only(top:10),
          child:pw.Text('Bank Reference: '+s.bankReference!,
            style:const pw.TextStyle(fontSize:9))),
      _heading('Payment Allocation by Fee Category'),
      _table(['Fee Category','Amount ('+s.currency+')'],[
        for(final c in s.categoryTotals.entries)[c.key,amount(c.value)],
      ]),
      _heading('Allocated Charges'),
      _table(['Billing Month','Fee Category','Payment ('+s.currency+')'],[
        for(final row in s.lines)[
          row.month.substring(0,7),row.category,amount(row.amountMinor)],
      ]),
      pw.SizedBox(height:12),
      pw.Container(
        padding:const pw.EdgeInsets.all(10),
        decoration:pw.BoxDecoration(
          border:pw.Border.all(color:PdfColors.grey700,width:0.8)),
        child:pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,
          children:[
            pw.Text('TOTAL RECEIVED',style:pw.TextStyle(
              fontSize:11,fontWeight:pw.FontWeight.bold)),
            pw.Text(s.currency+' '+amount(s.amountMinor),
              style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold)),
          ])),
      _heading('Previous Receipt History (same academic year, up to 5)'),
      _table(['Receipt','Date (UTC)','Paid ('+s.currency+')'],[
        for(final r in s.priorReceipts)[
          r.number,issued(r.issuedAt),amount(r.yearAllocated)],
      ]),
      pw.SizedBox(height:24),
      pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[
        pw.Text('Received By: ______________________',
          style:const pw.TextStyle(fontSize:9)),
        pw.Text('Signature / Stamp: ______________________',
          style:const pw.TextStyle(fontSize:9)),
      ]),
      pw.SizedBox(height:12),
      pw.Text('This receipt confirms only the amount collected above. '
        'Other outstanding fees may remain payable. '
        'All allocation details come from posted school records.',
        style:const pw.TextStyle(fontSize:8,color:PdfColors.grey700)),
      pw.SizedBox(height:8),
      pw.Text('Receipt ID: '+s.receiptId,
        style:const pw.TextStyle(fontSize:7,color:PdfColors.grey600)),
    ];
  }

  /// [copy] must be both, student, or office.
  static Future<Uint8List> build(FeeReceiptSlip slip,PdfPageFormat format,
      {String copy='both'}) async {
    if(!{'both','student','office'}.contains(copy)){
      throw const FormatException('Unknown receipt copy format');
    }
    if(slip.lines.isEmpty||slip.amountMinor<=0||
       slip.lines.fold<int>(0,(sum,x)=>sum+x.amountMinor)!=slip.amountMinor||
       slip.categoryTotals.values.fold<int>(0,(sum,x)=>sum+x)!=slip.amountMinor){
      throw const FormatException('Receipt cannot print unreconciled amounts');
    }
    final pdf=pw.Document(
      title:'Fee receipt '+slip.receiptNo,
      author:slip.schoolName,creator:'Supa Model School');
    void add(String label)=>pdf.addPage(pw.MultiPage(
      pageFormat:format,
      maxPages:50,
      margin:const pw.EdgeInsets.all(32),
      build:(context)=>_copy(slip,label),
      footer:(context)=>pw.Row(
        mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,
        children:[
          pw.Text('Generated from the immutable fee receipt',
            style:const pw.TextStyle(fontSize:7,color:PdfColors.grey600)),
          pw.Text('Page '+context.pageNumber.toString()+' of '+
            context.pagesCount.toString(),
            style:const pw.TextStyle(fontSize:7,color:PdfColors.grey600)),
        ])));
    if(copy=='both'||copy=='student')add('STUDENT COPY');
    if(copy=='both'||copy=='office')add('OFFICE COPY');
    return pdf.save();
  }
}
