import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../data/fee_detailed_statement.dart';
import '../data/fee_setup_repository.dart';

/// Produces a read-only school-year statement. All receipt amounts come from
/// server-reconciled allocations; the PDF itself never writes payment records.
class FeeStatementPdf {
  const FeeStatementPdf._();

  static String money(int value,String currency)=>
    currency+' '+FeeMoney.showMinor(value);

  static pw.Widget _section(String text)=>pw.Padding(
    padding:const pw.EdgeInsets.only(top:13,bottom:5),
    child:pw.Text(text,style:pw.TextStyle(
      fontSize:11,fontWeight:pw.FontWeight.bold)));

  static pw.Widget _table(List<String> headers,List<List<String>> data)=>
    pw.TableHelper.fromTextArray(
      headers:headers,
      data:data.isEmpty?
        [List<String>.filled(headers.length,'—')]:data,
      headerStyle:pw.TextStyle(fontSize:8,fontWeight:pw.FontWeight.bold),
      cellStyle:const pw.TextStyle(fontSize:7.5),
      headerDecoration:const pw.BoxDecoration(color:PdfColors.grey200),
      cellPadding:const pw.EdgeInsets.symmetric(vertical:4,horizontal:3),
      border:pw.TableBorder.all(color:PdfColors.grey300,width:0.4),
    );

  static Future<Uint8List> build(FeeDetailedStudentLedger r,
      PdfPageFormat format) async {
    r.validate();
    final pdf=pw.Document(
      title:'Fee statement - '+r.registration,
      author:r.schoolName,
      creator:'Supa Model School');
    String m(int amount)=>FeeMoney.showMinor(amount);
    pdf.addPage(pw.MultiPage(
      pageFormat:format,
      maxPages:400,
      margin:const pw.EdgeInsets.all(32),
      header:(context)=>pw.Column(
        crossAxisAlignment:pw.CrossAxisAlignment.start,
        children:[
          pw.Text(r.schoolName,style:pw.TextStyle(
            fontSize:15,fontWeight:pw.FontWeight.bold)),
          pw.Text('Student Fee Statement | Academic Year: '+r.yearLabel,
            style:const pw.TextStyle(fontSize:9)),
          pw.Divider(color:PdfColors.grey600),
        ]),
      footer:(context)=>pw.Row(
        mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,
        children:[
          pw.Text('Generated from posted charges and receipt allocations',
            style:const pw.TextStyle(fontSize:7,color:PdfColors.grey600)),
          pw.Text('Page '+context.pageNumber.toString()+
            ' of '+context.pagesCount.toString(),
            style:const pw.TextStyle(fontSize:7,color:PdfColors.grey600)),
        ]),
      build:(context)=>[
        pw.Text('Student: '+r.studentName+' | Admission: '+r.registration,
          style:pw.TextStyle(fontSize:10,fontWeight:pw.FontWeight.bold)),
        pw.Text('Class: '+r.className+
          (r.sectionName==null?'':' | Section: '+r.sectionName!),
          style:const pw.TextStyle(fontSize:9)),
        pw.SizedBox(height:10),
        _table(['Gross','Discount','Billed','Paid','Outstanding'],[[
          m(r.totals.gross),m(r.totals.discount),
          m(r.totals.net),m(r.totals.paid),m(r.totals.outstanding),
        ]]),
        _section('Category-wise fee totals'),
        _table(['Category','Charges','Billed','Paid','Outstanding'],[
          for(final x in r.categories)[
            x.label,x.totals.count.toString(),
            m(x.totals.net),m(x.totals.paid),m(x.totals.outstanding)],
        ]),
        _section('Monthly billing totals'),
        pw.Text('Paid values below are allocated against charges billed '
          'in that month, not cash received during that calendar month.',
          style:const pw.TextStyle(fontSize:8)),
        _table(['Billing Month','Charges','Billed','Paid','Outstanding'],[
          for(final x in r.months)[
            x.label.substring(0,7),x.totals.count.toString(),
            m(x.totals.net),m(x.totals.paid),m(x.totals.outstanding)],
        ]),
        _section('Detailed fee charges'),
        _table(['Month','Category','Description','Gross','Discount','Billed','Paid','Due'],[
          for(final c in r.charges)[
            c.month.substring(0,7),c.category,
            c.description.isEmpty?c.source:c.description,
            m(c.totals.gross),m(c.totals.discount),m(c.totals.net),
            m(c.totals.paid),m(c.totals.outstanding)],
        ]),
        _section('Payment receipts allocated to this academic year'),
        _table(['Receipt #','Issued At','Method','Receipt Total',
            'Allocated to Year'],[
          for(final receipt in r.receipts)[
            receipt.number,receipt.issuedAt.substring(0,10),
            receipt.method,m(receipt.total),m(receipt.yearAllocated)],
        ]),
        _section('Receipt allocations by fee charge'),
        _table(['Receipt #','Billing Month','Category','Amount'],[
          for(final a in r.allocations)[
            a.receiptNo,a.month.substring(0,7),a.category,m(a.amount)],
        ]),
        pw.SizedBox(height:14),
        pw.Text('End of statement. This report is not a payment receipt '
          'or proof of settlement of outstanding balances.',
          style:const pw.TextStyle(fontSize:8)),
      ],
    ));
    return pdf.save();
  }
}
