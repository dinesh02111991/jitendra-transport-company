import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  runApp(const TransportApp());
}

const navy = Color(0xff122c57);
const orange = Color(0xfff28c18);
final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final dateFmt = DateFormat('dd MMM yyyy');
String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());
double amount(dynamic x) => double.tryParse('${x ?? 0}') ?? 0;

class Store {
  static late Database db;
  static Future<void> init() async {
    final base = await getDatabasesPath();
    db = await openDatabase(p.join(base, 'jitendra_transport_v1.db'), version: 1,
      onCreate: (d, v) async {
        await d.execute('CREATE TABLE vehicles(id INTEGER PRIMARY KEY AUTOINCREMENT, registration TEXT NOT NULL UNIQUE, type TEXT NOT NULL, driver TEXT, phone TEXT)');
        await d.execute('CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, address TEXT, gstin TEXT)');
        await d.execute('CREATE TABLE trips(id INTEGER PRIMARY KEY AUTOINCREMENT, vehicle_id INTEGER, customer_id INTEGER, origin TEXT NOT NULL, destination TEXT NOT NULL, departure TEXT NOT NULL, arrival TEXT, freight REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT "In Transit", note TEXT)');
        await d.execute('CREATE TABLE expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id INTEGER, vehicle_id INTEGER, category TEXT NOT NULL, value REAL NOT NULL, spent_on TEXT NOT NULL, note TEXT)');
        await d.execute('CREATE TABLE documents(id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, doc_no TEXT NOT NULL UNIQUE, customer_id INTEGER, trip_id INTEGER, vehicle_id INTEGER, issued_on TEXT NOT NULL, consignor TEXT, consignee TEXT, goods TEXT, articles TEXT, weight TEXT, origin TEXT, destination TEXT, freight REAL NOT NULL DEFAULT 0, other REAL NOT NULL DEFAULT 0, paid REAL NOT NULL DEFAULT 0, note TEXT)');
        await d.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      });
  }
  static Future<List<Map<String,dynamic>>> rows(String table, {String order = 'id DESC'}) => db.query(table, orderBy: order);
  static Future<int> add(String table, Map<String,dynamic> data) => db.insert(table, data);
  static Future<int> update(String table, int id, Map<String,dynamic> data) => db.update(table, data, where:'id=?', whereArgs:[id]);
  static Future<int> remove(String table, int id) => db.delete(table, where:'id=?', whereArgs:[id]);
  static Future<String> setting(String key) async {
    final rows = await db.query('settings', where:'key=?', whereArgs:[key]);
    return rows.isEmpty ? '' : '${rows.first['value']}';
  }
  static Future<void> setSetting(String key, String value) async => db.insert('settings', {'key':key,'value':value}, conflictAlgorithm: ConflictAlgorithm.replace);
}

class TransportApp extends StatelessWidget {
  const TransportApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Jitendra Transport Company', debugShowCheckedModeBanner:false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: navy, primary: navy, secondary: orange), useMaterial3:true, scaffoldBackgroundColor:const Color(0xfff5f7fa), appBarTheme:const AppBarTheme(backgroundColor:navy,foregroundColor:Colors.white)),
    home:const Home());
}

class Home extends StatefulWidget { const Home({super.key}); @override State<Home> createState()=>_HomeState(); }
class _HomeState extends State<Home> {
  int tab=0; int refresh=0;
  void reload()=>setState(()=>refresh++);
  @override Widget build(BuildContext context) {
    final screens=[Dashboard(key:ValueKey('dash$refresh')), Vehicles(key:ValueKey('veh$refresh'),changed:reload), Trips(key:ValueKey('trip$refresh'),changed:reload), Documents(key:ValueKey('docs$refresh'),changed:reload), SettingsPage(key:ValueKey('settings$refresh'),changed:reload)];
    return Scaffold(appBar:AppBar(title:const Text('Jitendra Transport Company',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold))),body:screens[tab],
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const [
        NavigationDestination(icon:Icon(Icons.dashboard_outlined),label:'Home'),
        NavigationDestination(icon:Icon(Icons.local_shipping_outlined),label:'Vehicles'),
        NavigationDestination(icon:Icon(Icons.route_outlined),label:'Trips'),
        NavigationDestination(icon:Icon(Icons.receipt_long_outlined),label:'Bills'),
        NavigationDestination(icon:Icon(Icons.settings_outlined),label:'Settings')]));
  }
}

Widget panel({required Widget child})=>Card(elevation:0,color:Colors.white,margin:const EdgeInsets.symmetric(vertical:6),child:Padding(padding:const EdgeInsets.all(14),child:child));
Widget line(String label,String value)=>Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Row(children:[Expanded(child:Text(label,style:const TextStyle(color:Colors.black54))),Flexible(child:Text(value,textAlign:TextAlign.right,style:const TextStyle(fontWeight:FontWeight.w600)))]));
Widget heading(String s)=>Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Text(s,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold,color:navy)));
void snack(BuildContext c,String message)=>ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text(message)));

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  @override Widget build(BuildContext context)=>FutureBuilder(future:Future.wait([Store.rows('vehicles'),Store.rows('trips'),Store.rows('expenses'),Store.rows('documents')]),builder:(c,s){
    if(!s.hasData)return const Center(child:CircularProgressIndicator());
    final vehicles=s.data![0],trips=s.data![1],expenses=s.data![2],docs=s.data![3];
    final month=today().substring(0,7);
    final active=trips.where((t)=>t['status']=='In Transit').toList();
    // Revenue is counted from issued bills, not trips, to prevent double-counting.
    final revenue=docs.where((d)=>d['kind']=='Bill' && '${d['issued_on']}'.startsWith(month)).fold<double>(0,(a,d)=>a+amount(d['freight'])+amount(d['other']));
    final cost=expenses.where((e)=>'${e['spent_on']}'.startsWith(month)).fold<double>(0,(a,e)=>a+amount(e['value']));
    final outstanding=docs.where((d)=>d['kind']=='Bill').fold<double>(0,(a,d)=>a+amount(d['freight'])+amount(d['other'])-amount(d['paid']));
    return ListView(padding:const EdgeInsets.all(16),children:[
      Center(child:Image.asset('assets/logo.png',height:95,fit:BoxFit.contain)),
      heading('Business overview · ${DateFormat('MMMM yyyy').format(DateTime.now())}'),
      Wrap(spacing:8,runSpacing:8,children:[_metric('Vehicles', '${vehicles.length}',Icons.local_shipping),_metric('In transit','${active.length}',Icons.route),_metric('Revenue',money.format(revenue),Icons.trending_up),_metric('Expenses',money.format(cost),Icons.payments),_metric('Operating P/L',money.format(revenue-cost),Icons.analytics),_metric('Outstanding',money.format(outstanding),Icons.account_balance_wallet)]),
      heading('Currently in transit'),
      if(active.isEmpty)panel(child:const Text('No active trips. Add a trip from the Trips tab.')),
      ...active.map((t){final v=vehicles.where((v)=>v['id']==t['vehicle_id']);return panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(v.isEmpty?'Vehicle not assigned':'${v.first['registration']}',style:const TextStyle(fontWeight:FontWeight.bold)),Text('${t['origin']} → ${t['destination']}'),line('Departure','${t['departure']}')]));}),
      const SizedBox(height:14),const Text('P/L = bills issued this month minus expenses dated this month. It is an operating snapshot, not cash flow or tax profit.',style:TextStyle(color:Colors.black54,fontSize:12))
    ]);
  });
  Widget _metric(String label,String value,IconData icon)=>SizedBox(width:164,child:panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:orange),const SizedBox(height:8),Text(label,style:const TextStyle(color:Colors.black54)),Text(value,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:19),maxLines:1,overflow:TextOverflow.ellipsis)])));
}

class Field {
  final String label;final TextEditingController controller=TextEditingController();final bool number;
  Field(this.label,{String value='',this.number=false}) {controller.text=value;}
  Widget widget()=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:controller,keyboardType:number?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder(),isDense:true)));
  String get value=>controller.text.trim();
  void dispose()=>controller.dispose();
}
Future<bool> formDialog(BuildContext context,String title,List<Field> fields,Future<void> Function() save) async {
  final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(title),content:SizedBox(width:450,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:fields.map((f)=>f.widget()).toList()))),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:() async {try{await save();if(c.mounted)Navigator.pop(c,true);}catch(e){if(c.mounted)snack(c,'Unable to save: $e');}},child:const Text('Save'))]));
  for(final f in fields){f.dispose();}
  return ok??false;
}

class Vehicles extends StatefulWidget {final VoidCallback changed;const Vehicles({super.key,required this.changed});@override State<Vehicles> createState()=>_VehiclesState();}
class _VehiclesState extends State<Vehicles> {
  Future<void> edit([Map<String,dynamic>? v]) async {
    final fields=[Field('Vehicle registration *',value:'${v?['registration']??''}'),Field('Container type (20 Feet / 32 Feet) *',value:'${v?['type']??'32 Feet'}'),Field('Driver name',value:'${v?['driver']??''}'),Field('Driver mobile',value:'${v?['phone']??''}')];
    final saved=await formDialog(context,v==null?'Add vehicle':'Edit vehicle',fields,()async{
      if(fields[0].value.isEmpty||fields[1].value.isEmpty)throw Exception('Registration and type are required');
      final data={'registration':fields[0].value.toUpperCase(),'type':fields[1].value,'driver':fields[2].value,'phone':fields[3].value};
      if(v==null){await Store.add('vehicles',data);}else{await Store.update('vehicles',v['id'] as int,data);}
    });if(saved)widget.changed();
  }
  @override Widget build(BuildContext context)=>FutureBuilder(future:Store.rows('vehicles'),builder:(c,s)=>ListView(padding:const EdgeInsets.all(16),children:[heading('Fleet management'),FilledButton.icon(onPressed:()=>edit(),icon:const Icon(Icons.add),label:const Text('Add vehicle')),if(!s.hasData)const LinearProgressIndicator(),...?(s.data?.map((v)=>panel(child:ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.local_shipping,color:navy),title:Text('${v['registration']}'),subtitle:Text('${v['type']} · ${v['driver']??''}'),trailing:IconButton(onPressed:()=>edit(v),icon:const Icon(Icons.edit))))))]));
}

class Trips extends StatefulWidget {final VoidCallback changed;const Trips({super.key,required this.changed});@override State<Trips> createState()=>_TripsState();}
class _TripsState extends State<Trips> {
  Future<void> addTrip() async {
    final vs=await Store.rows('vehicles'),cs=await Store.rows('customers');
    if(vs.isEmpty){if(mounted)snack(context,'Add a vehicle first');return;}
    int? vehicle=vs.first['id'] as int;int? customer=cs.isEmpty?null:cs.first['id'] as int;
    final origin=Field('From *'),destination=Field('To *'),freight=Field('Freight amount',number:true),note=Field('Notes');
    if(!mounted)return;
    final saved=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setLocal)=>AlertDialog(title:const Text('New trip'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      DropdownButtonFormField<int>(initialValue:vehicle,decoration:const InputDecoration(labelText:'Vehicle'),items:vs.map((v)=>DropdownMenuItem(value:v['id'] as int,child:Text('${v['registration']}'))).toList(),onChanged:(x)=>setLocal(()=>vehicle=x)),
      if(cs.isNotEmpty)DropdownButtonFormField<int>(initialValue:customer,decoration:const InputDecoration(labelText:'Customer'),items:cs.map((x)=>DropdownMenuItem(value:x['id'] as int,child:Text('${x['name']}'))).toList(),onChanged:(x)=>setLocal(()=>customer=x)),
      origin.widget(),destination.widget(),freight.widget(),note.widget()]),),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()async{if(origin.value.isEmpty||destination.value.isEmpty){snack(c,'From and To are required');return;}await Store.add('trips',{'vehicle_id':vehicle,'customer_id':customer,'origin':origin.value,'destination':destination.value,'departure':today(),'freight':amount(freight.value),'status':'In Transit','note':note.value});if(c.mounted)Navigator.pop(c,true);},child:const Text('Start trip'))])));
    for(final f in [origin,destination,freight,note]){f.dispose();}
    if(saved==true)widget.changed();
  }
  Future<void> addExpense(Map<String,dynamic> t) async {
    final cat=Field('Category (Diesel, Toll, Driver, Repair) *'),value=Field('Amount *',number:true),note=Field('Notes');
    final saved=await formDialog(context,'Record trip expense',[cat,value,note],()async{
      if(cat.value.isEmpty||amount(value.value)<=0)throw Exception('Enter a category and positive amount');
      await Store.add('expenses',{'trip_id':t['id'],'vehicle_id':t['vehicle_id'],'category':cat.value,'value':amount(value.value),'spent_on':today(),'note':note.value});
    });if(saved)widget.changed();
  }
  @override Widget build(BuildContext context)=>FutureBuilder(future:Future.wait([Store.rows('trips'),Store.rows('vehicles'),Store.rows('expenses')]),builder:(c,s){
    final trips=s.data?[0]??[],vs=s.data?[1]??[],expenses=s.data?[2]??[];
    return ListView(padding:const EdgeInsets.all(16),children:[heading('Trips & expenses'),FilledButton.icon(onPressed:addTrip,icon:const Icon(Icons.add),label:const Text('Start new trip')),
      ...trips.map((t){final v=vs.where((x)=>x['id']==t['vehicle_id']);final cost=expenses.where((e)=>e['trip_id']==t['id']).fold<double>(0,(a,e)=>a+amount(e['value']));return panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${t['origin']} → ${t['destination']}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),line('Vehicle',v.isEmpty?'—':'${v.first['registration']}'),line('Status','${t['status']}'),line('Freight (planned)',money.format(amount(t['freight']))),line('Recorded expenses',money.format(cost)),Wrap(spacing:6,children:[TextButton.icon(onPressed:()=>addExpense(t),icon:const Icon(Icons.add),label:const Text('Expense')),if(t['status']=='In Transit')TextButton.icon(onPressed:()async{await Store.update('trips',t['id'] as int,{'status':'Delivered','arrival':today()});widget.changed();},icon:const Icon(Icons.check),label:const Text('Mark delivered'))])]));})]);
  });
}

class Documents extends StatefulWidget {final VoidCallback changed;const Documents({super.key,required this.changed});@override State<Documents> createState()=>_DocumentsState();}
class _DocumentsState extends State<Documents> {
  Future<void> addCustomer() async {
    final fields=[Field('Customer name *'),Field('Mobile'),Field('Address'),Field('GSTIN')];
    final saved=await formDialog(context,'New customer',fields,()async{if(fields[0].value.isEmpty)throw Exception('Customer name required');await Store.add('customers',{'name':fields[0].value,'phone':fields[1].value,'address':fields[2].value,'gstin':fields[3].value});});if(saved)widget.changed();
  }
  Future<void> createDocument(String kind) async {
    final cs=await Store.rows('customers'),vs=await Store.rows('vehicles'),ts=await Store.rows('trips');
    if(cs.isEmpty||vs.isEmpty){if(mounted)snack(context,'Add at least one customer and one vehicle first');return;}
    int customer=cs.first['id'] as int,vehicle=vs.first['id'] as int;int? trip;
    final fields=[Field('Consignor'),Field('Consignee'),Field('Goods description'),Field('No. of articles'),Field('Weight'),Field('From'),Field('To'),Field('Freight amount',number:true),Field('Other charges',number:true),Field('Amount received',number:true),Field('Remarks')];
    if(!mounted)return;
    final saved=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setLocal)=>AlertDialog(title:Text('New $kind'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      DropdownButtonFormField<int>(initialValue:customer,decoration:const InputDecoration(labelText:'Customer'),items:cs.map((x)=>DropdownMenuItem(value:x['id'] as int,child:Text('${x['name']}'))).toList(),onChanged:(x)=>setLocal(()=>customer=x!)),
      DropdownButtonFormField<int>(initialValue:vehicle,decoration:const InputDecoration(labelText:'Vehicle'),items:vs.map((x)=>DropdownMenuItem(value:x['id'] as int,child:Text('${x['registration']}'))).toList(),onChanged:(x)=>setLocal(()=>vehicle=x!)),
      DropdownButtonFormField<int?>(initialValue:trip,decoration:const InputDecoration(labelText:'Related trip (optional)'),items:[const DropdownMenuItem<int?>(value:null,child:Text('None')),...ts.map((x)=>DropdownMenuItem<int?>(value:x['id'] as int,child:Text('${x['origin']} → ${x['destination']}')))],onChanged:(x)=>setLocal(()=>trip=x)),
      ...fields.map((f)=>f.widget())])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()async{
        final prefix=kind=='Bill'?'JTC-B':'JTC-M';
        // SQLite insert and document sequence are serialized in one transaction.
        try {await Store.db.transaction((txn)async{
          final count=Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM documents WHERE kind=?',[kind]))??0;
          final num='$prefix-${DateTime.now().year}-${(count+1).toString().padLeft(5,'0')}';
          await txn.insert('documents',{'kind':kind,'doc_no':num,'customer_id':customer,'trip_id':trip,'vehicle_id':vehicle,'issued_on':today(),'consignor':fields[0].value,'consignee':fields[1].value,'goods':fields[2].value,'articles':fields[3].value,'weight':fields[4].value,'origin':fields[5].value,'destination':fields[6].value,'freight':amount(fields[7].value),'other':amount(fields[8].value),'paid':amount(fields[9].value),'note':fields[10].value});
        });if(c.mounted)Navigator.pop(c,true);}catch(e){if(c.mounted)snack(c,'Unable to save: $e');}
      },child:const Text('Create'))])));
    for(final f in fields){f.dispose();}
    if(saved==true)widget.changed();
  }
  @override Widget build(BuildContext context)=>FutureBuilder(future:Future.wait([Store.rows('documents'),Store.rows('customers'),Store.rows('vehicles')]),builder:(c,s){
    final docs=s.data?[0]??[],cs=s.data?[1]??[],vs=s.data?[2]??[];
    return ListView(padding:const EdgeInsets.all(16),children:[heading('Bills & transport memos'),Wrap(spacing:8,runSpacing:8,children:[FilledButton.icon(onPressed:()=>createDocument('Bill'),icon:const Icon(Icons.receipt),label:const Text('New bill')),FilledButton.tonalIcon(onPressed:()=>createDocument('Memo'),icon:const Icon(Icons.description),label:const Text('New memo')),OutlinedButton.icon(onPressed:addCustomer,icon:const Icon(Icons.person_add),label:Text('Add customer (${cs.length})'))]),
      ...docs.map((d){final customer=cs.where((x)=>x['id']==d['customer_id']);final vehicle=vs.where((x)=>x['id']==d['vehicle_id']);return panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${d['kind']} · ${d['doc_no']}',style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold)),line('Customer',customer.isEmpty?'—':'${customer.first['name']}'),line('Vehicle',vehicle.isEmpty?'—':'${vehicle.first['registration']}'),line('Total',money.format(amount(d['freight'])+amount(d['other']))),Align(alignment:Alignment.centerRight,child:FilledButton.icon(onPressed:()async{try{final file=await PdfService.make(d,customer.isEmpty?{}:customer.first,vehicle.isEmpty?{}:vehicle.first);await Share.shareXFiles([XFile(file.path,mimeType:'application/pdf')],text:'${d['kind']} ${d['doc_no']} — Jitendra Transport Company');}catch(e){if(context.mounted)snack(context,'PDF/share error: $e');}},icon:const Icon(Icons.share),label:const Text('Share PDF / WhatsApp')))]));})]);
  });
}

class SettingsPage extends StatefulWidget {final VoidCallback changed;const SettingsPage({super.key,required this.changed});@override State<SettingsPage> createState()=>_SettingsPageState();}
class _SettingsPageState extends State<SettingsPage> {
  Future<void> edit() async {
    final keys=['address','phone','gstin','bank','account','ifsc','terms'];
    final labels=['Business address','Business phone','GSTIN','Bank name','Account number','IFSC','Bill terms'];
    final fields=<Field>[];for(var i=0;i<keys.length;i++){fields.add(Field(labels[i],value:await Store.setting(keys[i])));}
    if(!mounted)return;
    final saved=await formDialog(context,'Business details',fields,()async{for(var i=0;i<keys.length;i++){await Store.setSetting(keys[i],fields[i].value);}});
    if(saved)widget.changed();
  }
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[heading('Business settings'),Center(child:Image.asset('assets/logo.png',height:120)),panel(child:const Text('JITENDRA TRANSPORT COMPANY',textAlign:TextAlign.center,style:TextStyle(fontWeight:FontWeight.bold))),FilledButton.icon(onPressed:edit,icon:const Icon(Icons.edit),label:const Text('Edit address, GST & bank details')),const SizedBox(height:14),panel(child:const Text('Offline storage: all records are kept in the app’s private SQLite database on this phone. Uninstalling or clearing app data may permanently delete records. A backup/export feature is not included in V1.'))]);
}

class PdfService {
  static Future<File> make(Map<String,dynamic> d,Map<String,dynamic> customer,Map<String,dynamic> vehicle) async {
    final pdf=pw.Document();
    final logo=pw.MemoryImage((await rootBundle.load('assets/logo.png')).buffer.asUint8List());
    final kind='${d['kind']}';
    final address=await Store.setting('address'),phone=await Store.setting('phone'),gst=await Store.setting('gstin');
    final bank=await Store.setting('bank'),account=await Store.setting('account'),ifsc=await Store.setting('ifsc'),terms=await Store.setting('terms');
    final navy=PdfColor.fromHex('#142B4F'), orange=PdfColor.fromHex('#F18A22'), pale=PdfColor.fromHex('#F3F6FA');
    final total=amount(d['freight'])+amount(d['other']);
    final received=amount(d['paid']);
    String val(dynamic v)=>'${v??''}'.trim().isEmpty?'—':'$v';
    String money(double n)=>'INR ${n.toStringAsFixed(2)}';
    pw.Widget cell(String label,dynamic value)=>pw.Container(padding:const pw.EdgeInsets.symmetric(vertical:7,horizontal:10),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[pw.Text(label.toUpperCase(),style:pw.TextStyle(fontSize:8,color:PdfColors.grey600,letterSpacing:.6)),pw.SizedBox(height:3),pw.Text(val(value),style:pw.TextStyle(fontSize:10,fontWeight:pw.FontWeight.bold,color:navy))]));
    pw.Widget section(String title)=>pw.Container(margin:const pw.EdgeInsets.only(top:17,bottom:8),child:pw.Text(title.toUpperCase(),style:pw.TextStyle(fontSize:10,color:navy,fontWeight:pw.FontWeight.bold,letterSpacing:1)));
    pw.Widget band(String title,String subtitle)=>pw.Container(padding:const pw.EdgeInsets.all(15),decoration:pw.BoxDecoration(color:navy,borderRadius:pw.BorderRadius.circular(8)),child:pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[pw.Text(title,style:pw.TextStyle(fontSize:18,fontWeight:pw.FontWeight.bold,color:PdfColors.white)),pw.SizedBox(height:4),pw.Text(subtitle,style:pw.TextStyle(fontSize:9,color:PdfColors.white))]),pw.Text(val(d['doc_no']),style:pw.TextStyle(color:PdfColors.white,fontSize:10,fontWeight:pw.FontWeight.bold))]));
    pw.Widget pair(String a,dynamic av,String b,dynamic bv)=>pw.Row(children:[pw.Expanded(child:pw.Container(color:pale,child:cell(a,av))),pw.SizedBox(width:7),pw.Expanded(child:pw.Container(color:pale,child:cell(b,bv)))]);
    pw.Widget line(String label,String value,{bool strong=false})=>pw.Container(padding:const pw.EdgeInsets.symmetric(vertical:7,horizontal:12),color:strong?pale:PdfColors.white,child:pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Text(label,style:pw.TextStyle(fontSize:10,fontWeight:strong?pw.FontWeight.bold:pw.FontWeight.normal)),pw.Text(value,style:pw.TextStyle(fontSize:10,fontWeight:pw.FontWeight.bold,color:navy))]));
    pdf.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.all(35),footer:(context)=>pw.Column(children:[pw.Divider(color:orange),pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Text('JITENDRA TRANSPORT COMPANY  •  Computer-generated document',style:const pw.TextStyle(fontSize:8,color:PdfColors.grey600)),pw.Text('Page ${context.pageNumber}',style:const pw.TextStyle(fontSize:8,color:PdfColors.grey600))])]),build:(context)=>[
      pw.Row(crossAxisAlignment:pw.CrossAxisAlignment.center,children:[pw.Image(logo,width:105,height:65,fit:pw.BoxFit.contain),pw.SizedBox(width:15),pw.Expanded(child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[pw.Text('JITENDRA TRANSPORT COMPANY',style:pw.TextStyle(fontSize:15,color:navy,fontWeight:pw.FontWeight.bold)),pw.SizedBox(height:4),pw.Text(address,style:const pw.TextStyle(fontSize:9)),pw.Text('Phone: $phone',style:const pw.TextStyle(fontSize:9)),if(gst.isNotEmpty)pw.Text('GSTIN: $gst',style:const pw.TextStyle(fontSize:9))]))]),
      pw.SizedBox(height:13),pw.Container(height:3,color:orange),pw.SizedBox(height:15),
      band(kind=='Bill'?'TRANSPORT BILL':'TRANSPORT MEMO',kind=='Bill'?'Freight & consignment statement':'Agreed freight quotation & vehicle placement'),
      pw.SizedBox(height:10),pair('Issue date',d['issued_on'],'Vehicle registration',vehicle['registration']),pw.SizedBox(height:7),pair('Customer / Transporter',customer['name'],'Container type',vehicle['type']),
      section('Journey details'),pair('Loading from',d['origin'],'Delivery to',d['destination']),pw.SizedBox(height:7),pair('Consignor',d['consignor'],'Consignee',d['consignee']),
      section('Goods & consignment'),pair('Goods description',d['goods'],'Number of articles',d['articles']),pw.SizedBox(height:7),pair('Weight',d['weight'],'Driver',vehicle['driver']),
      if(kind=='Bill') ...[
        section('Freight & payment summary'),
        pw.Container(decoration:pw.BoxDecoration(border:pw.Border.all(color:PdfColors.grey300),borderRadius:pw.BorderRadius.circular(6)),child:pw.Column(children:[line('Freight charges',money(amount(d['freight']))),pw.Divider(height:1,color:PdfColors.grey300),line('Additional charges',money(amount(d['other']))),pw.Divider(height:1,color:PdfColors.grey300),line('TOTAL BILL AMOUNT',money(total),strong:true),pw.Divider(height:1,color:PdfColors.grey300),line('Advance / amount received',money(received)),pw.Divider(height:1,color:PdfColors.grey300),line('BALANCE DUE',money(total-received),strong:true)])),
        section('Billing & payment details'),pair('Customer address',customer['address'],'Customer GSTIN',customer['gstin']),
        if(bank.isNotEmpty||account.isNotEmpty||ifsc.isNotEmpty)...[pw.SizedBox(height:7),pair('Bank / account', '$bank / $account','IFSC',ifsc)],
        if(terms.isNotEmpty)...[pw.SizedBox(height:9),pw.Text('Payment terms: $terms',style:const pw.TextStyle(fontSize:9))],
      ] else ...[
        section('Transport rate quotation'),
        pw.Container(padding:const pw.EdgeInsets.all(13),decoration:pw.BoxDecoration(color:pale,borderRadius:pw.BorderRadius.circular(6)),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
          pw.Text('To: ${val(customer['name'])}',style:pw.TextStyle(fontWeight:pw.FontWeight.bold,color:navy,fontSize:11)),
          pw.SizedBox(height:8),
          pw.Text('We confirm the following vehicle placement and freight quotation for transportation from ${val(d['origin'])} to ${val(d['destination'])}.',style:const pw.TextStyle(fontSize:10)),
        ])),
        pw.SizedBox(height:9),pair('Vehicle number',vehicle['registration'],'Container type',vehicle['type']),
        pw.SizedBox(height:7),pair('Quoted freight (INR)',money(amount(d['freight'])),'Advance (INR)',money(received)),
        pw.SizedBox(height:7),pair('Balance payable (INR)',money(amount(d['freight'])-received),'Other agreed charges (INR)',money(amount(d['other']))),
        section('Rate basis & payment conditions'),
        pw.Text('Freight rate basis (per MT / fixed trip), guaranteed tonnage if applicable, balance payment location and other agreed conditions must be entered in Remarks / special instructions before issuing.',style:const pw.TextStyle(fontSize:9)),
        section('Loading & transport conditions'),
        pw.Text('Please arrange loading and verify the required transport documents before dispatch. Confirm the agreed goods insurance, liability and payment conditions with the customer.',style:const pw.TextStyle(fontSize:9)),
      ],
      if(val(d['note'])!='—')...[section('Remarks / special instructions'),pw.Text(val(d['note']),style:const pw.TextStyle(fontSize:10))],
      pw.SizedBox(height:30),pw.Align(alignment:pw.Alignment.centerRight,child:pw.Column(children:[pw.Text('For JITENDRA TRANSPORT COMPANY',style:pw.TextStyle(color:navy,fontWeight:pw.FontWeight.bold,fontSize:10)),pw.SizedBox(height:30),pw.Text('Authorized Signatory',style:const pw.TextStyle(fontSize:9))]))
    ]));
    final dir=await getApplicationDocumentsDirectory();final pdfDir=Directory(p.join(dir.path,'pdfs'));await pdfDir.create(recursive:true);
    final file=File(p.join(pdfDir.path,'${d['doc_no']}.pdf'));await file.writeAsBytes(await pdf.save());return file;
  }
}
