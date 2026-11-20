import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/fee_setup_repository.dart';
import '../data/finance_overview_model.dart';

const _deepTeal=Color(0xFF005B54);
const _seaTeal=Color(0xFF009D85);
const _mint=Color(0xFF73D3C2);
const _navy=Color(0xFF183C49);
const _muted=Color(0xFF65818B);
const _canvas=Color(0xFFF3F9FC);

String financeDisplay(int minor,String currency)=>
  currency+' '+FeeMoney.showMinor(minor);

String _shortNum(int amount){
  final v=amount/100;
  if(v>=1000000)return (v/1000000).toStringAsFixed(1)+'m';
  if(v>=1000)return (v/1000).toStringAsFixed(0)+'k';
  return v.toStringAsFixed(0);
}

class FinanceOverviewBody extends StatelessWidget {
  const FinanceOverviewBody({
    super.key,required this.snapshot,required this.onCollect,
    required this.onTransport,required this.onSalaries,
    required this.onAddExpense,required this.onInvoice,
    required this.onReconciliation,required this.onReports,
    required this.onFeeSettings,
  });
  final FinanceOverviewSnapshot snapshot;
  final VoidCallback onCollect,onTransport,onSalaries,onAddExpense;
  final VoidCallback onInvoice,onReconciliation,onReports,onFeeSettings;

  @override
  Widget build(BuildContext context){
    final data=snapshot;
    return LayoutBuilder(builder:(context,layout){
      final width=layout.maxWidth;
      final cols=width>=1240?5:width>=820?3:width>=520?2:1;
      const gap=11.0;
      final tileWidth=math.max(1.0,(width-gap*(cols-1))/cols);
      final tiles=<Widget>[
        _MetricCard(label:'Total Collected',
          value:financeDisplay(data.collectedMinor,data.currency),
          note:'Fee receipts · last 6 months',icon:Icons.monetization_on_outlined,
          tint:const Color(0xFFE4FAED),iconColor:const Color(0xFF05975E)),
        _MetricCard(label:'Pending Fees',
          value:financeDisplay(data.pendingMinor,data.currency),
          note:'Outstanding · academic year',icon:Icons.warning_amber_rounded,
          tint:const Color(0xFFFFF3E1),iconColor:const Color(0xFFD98815)),
        _MetricCard(label:'Transport Fees',
          value:financeDisplay(data.transportMinor,data.currency),
          note:'Collected · last 6 months',icon:Icons.directions_bus_outlined,
          tint:const Color(0xFFE4FAED),iconColor:const Color(0xFF05975E)),
        _MetricCard(label:'Salaries (Paid)',
          value:financeDisplay(data.salariesMinor,data.currency),
          note:'Posted payouts · last 6 months',icon:Icons.groups_2_outlined,
          tint:const Color(0xFFE7F9F5),iconColor:_deepTeal),
        _MetricCard(label:'Other Expenses',
          value:financeDisplay(data.expensesMinor,data.currency),
          note:'Posted expenses · last 6 months',icon:Icons.receipt_long_outlined,
          tint:const Color(0xFFFFF3E8),iconColor:const Color(0xFFCE7924)),
      ];
      return ListView(key:const Key('finance-overview-live'),
        padding:EdgeInsets.all(width<600?12:18),children:[
        LayoutBuilder(builder:(context,box)=>Wrap(
          spacing:gap,runSpacing:gap,children:[
            for(final card in tiles)
              SizedBox(width:tileWidth,child:card),
          ])),
        const SizedBox(height:13),
        if(width>=970)
          Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Expanded(flex:6,child:_TrendPanel(data:data)),
            const SizedBox(width:13),
            Expanded(flex:5,child:_CategoryPanel(data:data)),
          ])
        else Column(children:[
          _TrendPanel(data:data),
          const SizedBox(height:13),
          _CategoryPanel(data:data),
        ]),
        const SizedBox(height:13),
        if(width>=940)
          Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Expanded(flex:6,child:_RecentTransactions(
              snapshot:data,onViewAll:onReports,compact:false)),
            const SizedBox(width:13),
            Expanded(flex:5,child:_QuickActions(
              onCollect:onCollect,onTransport:onTransport,
              onSalaries:onSalaries,onAddExpense:onAddExpense,
              onInvoice:onInvoice,onReconciliation:onReconciliation,
              onReports:onReports,onFeeSettings:onFeeSettings)),
          ])
        else Column(children:[
          _RecentTransactions(snapshot:data,onViewAll:onReports,
            compact:width<650),
          const SizedBox(height:13),
          _QuickActions(
            onCollect:onCollect,onTransport:onTransport,
            onSalaries:onSalaries,onAddExpense:onAddExpense,
            onInvoice:onInvoice,onReconciliation:onReconciliation,
            onReports:onReports,onFeeSettings:onFeeSettings),
        ]),
        const SizedBox(height:8),
        Padding(padding:const EdgeInsets.symmetric(vertical:10),
          child:Text('Amounts reflect authorized posted school records. '
            'Collection trends use receipt dates; pending fees are all '
            'outstanding charges for the academic year. '
            'Cash movement is not accounting profit.',
            textAlign:TextAlign.center,
            style:TextStyle(fontSize:11,
              color:Theme.of(context).brightness==Brightness.dark?
                Colors.white70:_muted))),
      ]);
    });
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override Widget build(BuildContext context){
    final dark=Theme.of(context).brightness==Brightness.dark;
    return Container(
      decoration:BoxDecoration(
        color:dark?Theme.of(context).colorScheme.surface:
          Colors.white,
        borderRadius:BorderRadius.circular(15),
        border:Border.all(color:dark?Theme.of(context).dividerColor:
          const Color(0xFFDCEBF0)),
        boxShadow:dark?null:const [
          BoxShadow(color:Color(0x170C5973),blurRadius:10,
            offset:Offset(0,4)),
        ],
      ),
      padding:const EdgeInsets.all(15),child:child);
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,required this.value,required this.note,
    required this.icon,required this.tint,required this.iconColor});
  final String label,value,note;
  final IconData icon;
  final Color tint,iconColor;
  @override Widget build(BuildContext context){
    final dark=Theme.of(context).brightness==Brightness.dark;
    return Container(
      key:Key('finance-kpi-'+label.toLowerCase().replaceAll(
        RegExp(r'[^a-z]+'),'-')),
      constraints:const BoxConstraints(minHeight:118),
      padding:const EdgeInsets.all(13),
      decoration:BoxDecoration(
        color:dark?Theme.of(context).colorScheme.surface:Colors.white,
        borderRadius:BorderRadius.circular(14),
        border:Border.all(color:dark?Theme.of(context).dividerColor:
          const Color(0xFFDEECF0)),
        boxShadow:dark?null:const [
          BoxShadow(color:Color(0x16095463),blurRadius:8,offset:Offset(0,4)),
        ]),
      child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Container(padding:const EdgeInsets.all(10),
          decoration:BoxDecoration(color:tint,
            borderRadius:BorderRadius.circular(11)),
          child:Icon(icon,color:iconColor,size:26)),
        const SizedBox(width:11),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
          children:[
          Text(label,maxLines:1,overflow:TextOverflow.ellipsis,
            style:TextStyle(fontSize:12,fontWeight:FontWeight.w700,
              color:dark?Colors.white:_navy)),
          const SizedBox(height:6),
          FittedBox(fit:BoxFit.scaleDown,
            alignment:Alignment.centerLeft,
            child:Text(value,style:TextStyle(
              fontSize:19,fontWeight:FontWeight.w900,
              color:dark?_mint:_deepTeal))),
          const SizedBox(height:6),
          Text(note,maxLines:2,overflow:TextOverflow.ellipsis,
            style:TextStyle(fontSize:10,color:dark?Colors.white70:_muted)),
        ])),
      ]),
    );
  }
}

class _TrendPanel extends StatelessWidget{
  const _TrendPanel({required this.data});
  final FinanceOverviewSnapshot data;
  @override Widget build(BuildContext context){
    return _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          const Icon(Icons.analytics_outlined,color:_seaTeal),
          const SizedBox(width:8),
          Expanded(child:Text('Fee Collection Trend',
            style:Theme.of(context).textTheme.titleMedium?.copyWith(
              color:Theme.of(context).brightness==Brightness.dark?
                Colors.white:_deepTeal,fontWeight:FontWeight.w800))),
          Text('Last 6 Months',style:TextStyle(
            color:Theme.of(context).brightness==Brightness.dark?
              Colors.white70:_muted,fontSize:11)),
        ]),
        const SizedBox(height:4),
        Text('Collected by receipt date · '+data.currency,
          style:const TextStyle(fontSize:11,color:_muted)),
        const SizedBox(height:10),
        SizedBox(height:211,
          child:CustomPaint(
            key:const Key('finance-collection-trend-chart'),
            painter:_TrendPainter(data.trend,
              Theme.of(context).brightness==Brightness.dark))),
      ]));
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.data,this.dark);
  final List<FinanceTrendMonth> data;
  final bool dark;

  void _text(Canvas canvas,String value,double x,double y,
      {double size=10,Color color=_muted,TextAlign alignment=TextAlign.left}){
    final painter=TextPainter(
      text:TextSpan(text:value,
        style:TextStyle(color:dark?Colors.white70:color,fontSize:size)),
      textDirection:TextDirection.ltr,textAlign:alignment)..layout();
    final left=alignment==TextAlign.center?x-painter.width/2:
      alignment==TextAlign.right?x-painter.width:x;
    painter.paint(canvas,Offset(left,y));
  }

  @override void paint(Canvas canvas,Size size){
    if(data.isEmpty)return;
    final left=46.0,right=size.width-9,top=10.0,bottom=size.height-28;
    final w=math.max(1.0,right-left),h=math.max(1.0,bottom-top);
    var maxValue=1;
    for(final month in data){
      maxValue=math.max(maxValue,month.amountMinor);
    }
    final step=maxValue/4;
    final gridPaint=Paint()..color=dark?Colors.white24:
      const Color(0xFFE1EBEF)..strokeWidth=1;
    for(var n=0;n<=4;n++){
      final y=bottom-h*n/4;
      canvas.drawLine(Offset(left,y),Offset(right,y),gridPaint);
      final amount=(step*n).round();
      _text(canvas,_shortNum(amount),left-5,y-6,
        size:9,alignment:TextAlign.right);
    }
    final slot=w/data.length;
    final line=Path();
    final centers=<Offset>[];
    for(var i=0;i<data.length;i++){
      final value=data[i].amountMinor;
      final ratio=value/maxValue;
      final x=left+slot*(i+0.5);
      final y=bottom-h*ratio;
      final bw=math.min(slot*0.53,48.0);
      final rect=Rect.fromLTWH(x-bw/2,y,bw,math.max(0,bottom-y));
      if(rect.height>0){
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect,
            topLeft:const Radius.circular(5),
            topRight:const Radius.circular(5)),
          Paint()..shader=const LinearGradient(
            begin:Alignment.bottomCenter,end:Alignment.topCenter,
            colors:[_deepTeal,_seaTeal]).createShader(rect));
      }
      centers.add(Offset(x,y));
      if(i==0){line.moveTo(x,y);}else{line.lineTo(x,y);}
      final d=DateTime.tryParse(data[i].month+'-01');
      _text(canvas,d==null?data[i].month:
        financeMonthNames[d.month-1]+' '+d.year.toString().substring(2),
        x,bottom+7,size:9,alignment:TextAlign.center);
    }
    if(centers.length>=2){
      canvas.drawPath(line,Paint()
        ..color=_mint..strokeWidth=2.2..style=PaintingStyle.stroke);
    }
    for(final pt in centers){
      canvas.drawCircle(pt,3.7,Paint()..color=Colors.white);
      canvas.drawCircle(pt,2.3,Paint()..color=_seaTeal);
    }
  }
  @override bool shouldRepaint(covariant _TrendPainter old)=>
    old.dark!=dark||old.data!=data;
}

class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({required this.data});
  final FinanceOverviewSnapshot data;
  @override Widget build(BuildContext context){
    final all=data.collectedMinor;
    final entries=[
      ('Tuition Fee',data.tuitionMinor,_seaTeal),
      ('Transport Fee',data.transportMinor,const Color(0xFF72D3C1)),
      ('Other Fees',data.otherFeesMinor,const Color(0xFFB4EAE1)),
    ];
    return _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          const Icon(Icons.pie_chart_outline,color:_seaTeal),
          const SizedBox(width:8),
          Text('Collection by Category',
            style:Theme.of(context).textTheme.titleMedium?.copyWith(
              color:Theme.of(context).brightness==Brightness.dark?
                Colors.white:_deepTeal,fontWeight:FontWeight.w800)),
        ]),
        const SizedBox(height:16),
        LayoutBuilder(builder:(context,box){
          final compact=box.maxWidth<420;
          final ring=Stack(alignment:Alignment.center,children:[
            SizedBox(width:170,height:170,child:CustomPaint(
              key:const Key('finance-category-donut'),
              painter:_RingPainter([
                for(final row in entries)row.$2,
              ],[for(final row in entries)row.$3]))),
            SizedBox(width:124,child:Column(children:[
              FittedBox(child:Text(financeDisplay(all,data.currency),
                style:TextStyle(fontWeight:FontWeight.w800,fontSize:17,
                  color:Theme.of(context).brightness==Brightness.dark?
                    _mint:_deepTeal))),
              const SizedBox(height:4),
              const Text('Total Collected',style:TextStyle(
                fontSize:10,color:_muted)),
            ])),
          ]);
          final legend=Column(children:[
            for(final entry in entries)
              Padding(padding:const EdgeInsets.symmetric(vertical:7),
                child:Row(children:[
                  Container(width:13,height:13,
                    decoration:BoxDecoration(color:entry.$3,
                      borderRadius:BorderRadius.circular(3))),
                  const SizedBox(width:8),
                  Expanded(child:Text(entry.$1,
                    style:const TextStyle(fontSize:12))),
                  const SizedBox(width:6),
                  Text(all==0?'0.0%':
                    (100*entry.$2/all).toStringAsFixed(1)+'%',
                    style:const TextStyle(fontSize:11,
                      fontWeight:FontWeight.w800)),
                  const SizedBox(width:6),
                  Text(financeDisplay(entry.$2,data.currency),
                    style:const TextStyle(fontSize:10)),
                ])),
          ]);
          return compact
            ?Column(children:[ring,const SizedBox(height:8),legend])
            :Row(children:[
              ring,const SizedBox(width:8),
              Expanded(child:legend),
            ]);
        }),
        const SizedBox(height:10),
      ]));
  }
}

class _RingPainter extends CustomPainter{
  _RingPainter(this.amounts,this.colors);
  final List<int> amounts;
  final List<Color> colors;
  @override void paint(Canvas canvas,Size size){
    final total=amounts.fold<int>(0,(sum,x)=>sum+x);
    final center=Offset(size.width/2,size.height/2);
    final radius=math.min(size.width,size.height)/2-13;
    final bounds=Rect.fromCircle(center:center,radius:radius);
    canvas.drawArc(bounds,0,2*math.pi,false,Paint()
      ..style=PaintingStyle.stroke..strokeWidth=20
      ..color=const Color(0xFFE6F1F0));
    if(total<=0)return;
    var start=-math.pi/2;
    for(var i=0;i<amounts.length;i++){
      if(amounts[i]<=0)continue;
      final sweep=2*math.pi*amounts[i]/total;
      canvas.drawArc(bounds,start,sweep,false,Paint()
        ..style=PaintingStyle.stroke..strokeWidth=20
        ..strokeCap=StrokeCap.butt..color=colors[i]);
      start+=sweep;
    }
  }
  @override bool shouldRepaint(covariant _RingPainter old)=>true;
}

class _RecentTransactions extends StatelessWidget{
  const _RecentTransactions({
    required this.snapshot,required this.onViewAll,required this.compact});
  final FinanceOverviewSnapshot snapshot;
  final VoidCallback onViewAll;
  final bool compact;
  @override Widget build(BuildContext context){
    final rows=snapshot.transactions.take(6).toList();
    return _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          const Icon(Icons.receipt_long_outlined,color:_seaTeal),
          const SizedBox(width:8),
          Expanded(child:Text('Recent Transactions',
            style:Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight:FontWeight.w800,
              color:Theme.of(context).brightness==Brightness.dark?
                Colors.white:_deepTeal))),
          TextButton(key:const Key('finance-view-all-transactions'),
            onPressed:onViewAll,child:const Text('View All')),
        ]),
        const SizedBox(height:7),
        if(rows.isEmpty)
          const Padding(padding:EdgeInsets.all(16),
            child:Text('No posted transactions in this period.'))
        else if(compact)
          for(final row in rows)
            ListTile(
              dense:true,
              title:Text(row.category+' · '+row.counterparty,
                maxLines:2,overflow:TextOverflow.ellipsis),
              subtitle:Text(row.date+' · '+row.method),
              trailing:Text(financeDisplay(row.amountMinor.abs(),
                snapshot.currency),
                style:TextStyle(fontSize:11,fontWeight:FontWeight.w800,
                  color:row.isIncome?_seaTeal:Colors.redAccent)))
        else ...[
          Container(padding:const EdgeInsets.symmetric(
            vertical:9,horizontal:8),
            decoration:BoxDecoration(
              color:const Color(0xFFEFF5F8),
              borderRadius:BorderRadius.circular(6)),
            child:const Row(children:[
              SizedBox(width:85,child:Text('Date',
                style:TextStyle(fontSize:11,fontWeight:FontWeight.w700))),
              Expanded(flex:3,child:Text('Particulars',
                style:TextStyle(fontSize:11,fontWeight:FontWeight.w700))),
              Expanded(flex:2,child:Text('Category',
                style:TextStyle(fontSize:11,fontWeight:FontWeight.w700))),
              Expanded(flex:2,child:Text('Amount',
                style:TextStyle(fontSize:11,fontWeight:FontWeight.w700))),
              SizedBox(width:70,child:Text('Type',
                style:TextStyle(fontSize:11,fontWeight:FontWeight.w700))),
            ]),
          ),
          for(final row in rows)
            Padding(
              padding:const EdgeInsets.symmetric(horizontal:8,vertical:6),
              child:Row(children:[
                SizedBox(width:85,child:Text(
                  row.date.length>=10?row.date.substring(0,10):row.date,
                  style:const TextStyle(fontSize:10))),
                Expanded(flex:3,child:Text(row.counterparty+
                  (row.reference.isEmpty?'':' · '+row.reference),
                  maxLines:1,overflow:TextOverflow.ellipsis,
                  style:const TextStyle(fontSize:11))),
                Expanded(flex:2,child:Text(row.category,maxLines:1,
                  overflow:TextOverflow.ellipsis,
                  style:const TextStyle(fontSize:11))),
                Expanded(flex:2,child:Text(
                  financeDisplay(row.amountMinor.abs(),snapshot.currency),
                  maxLines:1,overflow:TextOverflow.ellipsis,
                  style:const TextStyle(fontSize:11,
                    fontWeight:FontWeight.w700))),
                SizedBox(width:70,child:Container(
                  padding:const EdgeInsets.symmetric(
                    horizontal:5,vertical:5),
                  decoration:BoxDecoration(
                    color:row.isIncome?const Color(0xFFE3F9ED):
                      const Color(0xFFFFE9E8),
                    borderRadius:BorderRadius.circular(20)),
                  child:Text(row.isIncome?'Receipt':'Payment',
                    textAlign:TextAlign.center,
                    style:TextStyle(fontSize:10,
                      color:row.isIncome?const Color(0xFF148750):
                        const Color(0xFFB8504C)))),
                ),
              ]),
            ),
        ],
      ]));
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onCollect,required this.onTransport,
    required this.onSalaries,required this.onAddExpense,
    required this.onInvoice,required this.onReconciliation,
    required this.onReports,required this.onFeeSettings});
  final VoidCallback onCollect,onTransport,onSalaries,onAddExpense;
  final VoidCallback onInvoice,onReconciliation,onReports,onFeeSettings;

  @override Widget build(BuildContext context){
    final actions=<({String name,IconData icon,VoidCallback tap})>[
      (name:'Collect Fee',icon:Icons.note_add_outlined,tap:onCollect),
      (name:'Transport Fee',icon:Icons.directions_bus_outlined,tap:onTransport),
      (name:'Pay Salary',icon:Icons.groups_2_outlined,tap:onSalaries),
      (name:'Add Expense',icon:Icons.account_balance_wallet_outlined,
        tap:onAddExpense),
      (name:'Create Invoice',icon:Icons.receipt_long_outlined,tap:onInvoice),
      (name:'Fee Reconciliation',icon:Icons.sync_alt_outlined,
        tap:onReconciliation),
      (name:'Finance Reports',icon:Icons.bar_chart_outlined,
        tap:onReports),
      (name:'Fee Settings',icon:Icons.settings_outlined,tap:onFeeSettings),
    ];
    return _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          const Icon(Icons.bolt_outlined,color:_seaTeal),
          const SizedBox(width:8),
          Text('Quick Actions',
            style:Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight:FontWeight.w800,
              color:Theme.of(context).brightness==Brightness.dark?
                Colors.white:_deepTeal)),
        ]),
        const SizedBox(height:14),
        LayoutBuilder(builder:(context,box){
          final n=box.maxWidth>=310?4:2;
          final width=math.max(1.0,(box.maxWidth-8*(n-1))/n);
          return Wrap(spacing:8,runSpacing:8,children:[
            for(final a in actions)
              SizedBox(width:width,height:84,child:Material(
                color:Theme.of(context).brightness==Brightness.dark?
                  Theme.of(context).colorScheme.surface:
                  const Color(0xFFF6F9FC),
                borderRadius:BorderRadius.circular(11),
                child:InkWell(
                  key:Key('finance-action-'+a.name.toLowerCase()
                    .replaceAll(RegExp(r'[^a-z]+'),'-')),
                  onTap:a.tap,borderRadius:BorderRadius.circular(11),
                  child:Container(
                    padding:const EdgeInsets.all(6),
                    decoration:BoxDecoration(
                      borderRadius:BorderRadius.circular(11),
                      border:Border.all(
                        color:const Color(0xFFDCE8ED))),
                    child:Column(
                      mainAxisAlignment:MainAxisAlignment.center,
                      children:[
                        Icon(a.icon,color:_deepTeal,size:26),
                        const SizedBox(height:7),
                        Text(a.name,textAlign:TextAlign.center,
                          maxLines:2,overflow:TextOverflow.ellipsis,
                          style:const TextStyle(fontSize:10,
                            fontWeight:FontWeight.w600)),
                      ])),
                  ))),
          ]);
        }),
      ]));
  }
}

/// The screenshot's Salaries/Other sections display actual posted movement
/// records, with navigation into the existing full modules.
class FinanceMovementPanel extends StatelessWidget{
  const FinanceMovementPanel({super.key,required this.snapshot,
    required this.salaries,required this.onOpenModule});
  final FinanceOverviewSnapshot snapshot;
  final bool salaries;
  final VoidCallback onOpenModule;

  @override Widget build(BuildContext context){
    final rows=snapshot.transactions.where((e)=>
      salaries?e.isSalary:e.isExpense).toList();
    final total=salaries?snapshot.salariesMinor:snapshot.expensesMinor;
    return ListView(key:Key(salaries?'finance-salary-live':'finance-other-live'),
      padding:const EdgeInsets.all(18),children:[
        _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Text(salaries?'Salary Payments':'Other Expenses',
              style:Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height:4),
            Text('Posted movements · '+snapshot.periodStart+
              ' to '+snapshot.periodEnd,
              style:const TextStyle(color:_muted)),
            const SizedBox(height:10),
            Text(financeDisplay(total,snapshot.currency),
              style:Theme.of(context).textTheme.headlineMedium?.copyWith(
                color:_deepTeal,fontWeight:FontWeight.bold)),
            const SizedBox(height:12),
            OutlinedButton.icon(onPressed:onOpenModule,
              icon:Icon(salaries?Icons.badge_outlined:
                Icons.receipt_long_outlined),
              label:Text(salaries?'Open Payroll':'Open Expenses')),
          ])),
        const SizedBox(height:12),
        _Panel(child:Column(children:[
          Row(children:[
            const Icon(Icons.list_alt_outlined,color:_seaTeal),
            const SizedBox(width:8),
            Expanded(child:Text(salaries?'Recent Salary Movements':
              'Recent Expense Movements',
              style:Theme.of(context).textTheme.titleMedium)),
          ]),
          if(rows.isEmpty)
            const Padding(padding:EdgeInsets.all(18),
              child:Text('No posted transactions were returned for '
                'this reporting period.'))
          else for(final e in rows.take(35))
            ListTile(
              title:Text(e.counterparty+' · '+e.category),
              subtitle:Text(e.date+' · '+e.reference+' · '+e.method),
              trailing:Text(financeDisplay(
                e.amountMinor.abs(),snapshot.currency))),
        ])),
      ]);
  }
}
