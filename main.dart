import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const DairyBillApp());

const products = <String, int>{
  'Amul Taaza': 29,
  'Amul Gold': 35,
  'Chaas': 20,
};

String dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
String monthKey(DateTime date) => DateFormat('yyyy-MM').format(date);
String money(int value) => '₹$value';

class Customer {
  final String id;
  String name;
  String phone;
  Customer({required this.id, required this.name, this.phone = ''});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone};
  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: (json['phone'] ?? '') as String,
      );
}

class MilkEntry {
  final String id;
  final String customerId;
  final String customerName;
  final String date;
  final Map<String, int> quantities;
  final String note;
  MilkEntry({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.quantities,
    this.note = '',
  });
  int get total => quantities.entries.fold(0, (sum, item) => sum + item.value * (products[item.key] ?? 0));
  Map<String, dynamic> toJson() => {
        'id': id,
        'customerId': customerId,
        'customerName': customerName,
        'date': date,
        'quantities': quantities,
        'note': note,
      };
  factory MilkEntry.fromJson(Map<String, dynamic> json) => MilkEntry(
        id: json['id'] as String,
        customerId: json['customerId'] as String,
        customerName: json['customerName'] as String,
        date: json['date'] as String,
        quantities: (json['quantities'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toInt())),
        note: (json['note'] ?? '') as String,
      );
}

class DairyBillApp extends StatelessWidget {
  const DairyBillApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Dairy Bill',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1557A6)),
          scaffoldBackgroundColor: const Color(0xFFF5F7FB),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1557A6), foregroundColor: Colors.white),
          cardTheme: CardThemeData(elevation: 0, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  bool loading = true;
  List<Customer> customers = [];
  List<MilkEntry> entries = [];
  String? selectedCustomerId;
  DateTime entryDate = DateTime.now();
  final Map<String, TextEditingController> quantityControllers = {
    for (final product in products.keys) product: TextEditingController(text: '0'),
  };
  final noteController = TextEditingController();

  Customer? get selectedCustomer {
    for (final customer in customers) {
      if (customer.id == selectedCustomerId) return customer;
    }
    return null;
  }
  int quantity(String product) => int.tryParse(quantityControllers[product]!.text) ?? 0;
  int get draftTotal => products.entries.fold(0, (sum, item) => sum + quantity(item.key) * item.value);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawCustomers = prefs.getString('ml_customers');
    final rawEntries = prefs.getString('ml_entries');
    setState(() {
      customers = rawCustomers == null
          ? []
          : (jsonDecode(rawCustomers) as List).map((e) => Customer.fromJson(Map<String, dynamic>.from(e))).toList();
      entries = rawEntries == null
          ? []
          : (jsonDecode(rawEntries) as List).map((e) => MilkEntry.fromJson(Map<String, dynamic>.from(e))).toList();
      selectedCustomerId = customers.isEmpty ? null : customers.first.id;
      loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ml_customers', jsonEncode(customers.map((e) => e.toJson()).toList()));
    await prefs.setString('ml_entries', jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addCustomer({Customer? editing}) async {
    final nameController = TextEditingController(text: editing?.name ?? '');
    final phoneController = TextEditingController(text: editing?.phone ?? '');
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(editing == null ? 'Add customer' : 'Edit customer'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameController, textCapitalization: TextCapitalization.words, autofocus: true, decoration: const InputDecoration(labelText: 'Customer name', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 12),
          TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)', prefixIcon: Icon(Icons.phone_outlined))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, {'name': nameController.text.trim(), 'phone': phoneController.text.trim()}), child: const Text('Save')),
        ],
      ),
    );
    nameController.dispose();
    phoneController.dispose();
    if (result == null) return;
    final name = result['name'] ?? '';
    if (name.isEmpty) { _message('Enter a customer name.'); return; }
    final duplicate = customers.any((c) => c.name.toLowerCase() == name.toLowerCase() && c.id != editing?.id);
    if (duplicate) { _message('That customer already exists.'); return; }
    setState(() {
      if (editing != null) {
        editing.name = name;
        editing.phone = result['phone'] ?? '';
        for (final entry in entries.where((e) => e.customerId == editing.id)) {
          // Historical entries retain the original name on purpose.
        }
      } else {
        final customer = Customer(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name, phone: result['phone'] ?? '');
        customers.add(customer);
        selectedCustomerId = customer.id;
      }
    });
    await _save();
  }

  Future<void> _deleteCustomer(Customer customer) async {
    final hasEntries = entries.any((e) => e.customerId == customer.id);
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete customer?'),
      content: Text(hasEntries ? 'This customer has saved entries. The customer will be removed from the list, but past records will remain.' : 'Remove ${customer.name} from the customer list?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))],
    ));
    if (confirmed != true) return;
    setState(() {
      customers.removeWhere((c) => c.id == customer.id);
      if (selectedCustomerId == customer.id) selectedCustomerId = customers.isEmpty ? null : customers.first.id;
    });
    await _save();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: entryDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked != null) setState(() => entryDate = picked);
  }

  Future<void> _saveEntry() async {
    final customer = selectedCustomer;
    if (customer == null) { _message('Add a customer first.'); return; }
    if (products.keys.every((p) => quantity(p) == 0)) { _message('Enter at least one packet quantity.'); return; }
    final badQuantity = products.keys.any((p) => quantity(p) < 0);
    if (badQuantity) { _message('Quantities cannot be negative.'); return; }
    final entry = MilkEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      customerId: customer.id,
      customerName: customer.name,
      date: dateKey(entryDate),
      quantities: {for (final product in products.keys) product: quantity(product)},
      note: noteController.text.trim(),
    );
    setState(() {
      entries.add(entry);
      for (final controller in quantityControllers.values) { controller.text = '0'; }
      noteController.clear();
      tab = 2;
    });
    await _save();
    _message('Entry saved for ${customer.name}.');
  }

  List<MilkEntry> _customerMonthEntries(String customerId, DateTime month) => entries.where((e) => e.customerId == customerId && e.date.startsWith(monthKey(month))).toList()..sort((a, b) => a.date.compareTo(b.date));
  int _billTotal(List<MilkEntry> list) => list.fold(0, (sum, e) => sum + e.total);
  int _billQuantity(List<MilkEntry> list, String product) => list.fold(0, (sum, e) => sum + (e.quantities[product] ?? 0));

  Future<void> _exportBill(Customer customer, DateTime month) async {
    final list = _customerMonthEntries(customer.id, month);
    final doc = pw.Document();
    final totals = {for (final product in products.keys) product: _billQuantity(list, product)};
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, build: (context) => [
      pw.Text('MILK MONTHLY BILL', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      pw.Text('Customer: ${customer.name}'),
      if (customer.phone.isNotEmpty) pw.Text('Phone: ${customer.phone}'),
      pw.Text('Billing month: ${DateFormat('MMMM yyyy').format(month)}'),
      pw.SizedBox(height: 20),
      pw.TableHelper.fromTextArray(
        headers: ['Product', 'Packets', 'Rate', 'Amount'],
        data: products.entries.map((p) => [p.key, '${totals[p.key]}', 'Rs. ${p.value}', 'Rs. ${totals[p.key]! * p.value}']).toList(),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        cellAlignment: pw.Alignment.centerLeft,
      ),
      pw.SizedBox(height: 16),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('TOTAL DUE: Rs. ${_billTotal(list)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 20),
      pw.Text('Daily details', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      if (list.isEmpty) pw.Text('No entries recorded for this month.'),
      if (list.isNotEmpty) pw.TableHelper.fromTextArray(
        headers: ['Date', 'Taaza', 'Gold', 'Chaas', 'Amount'],
        data: list.map((e) => [e.date, '${e.quantities['Amul Taaza'] ?? 0}', '${e.quantities['Amul Gold'] ?? 0}', '${e.quantities['Chaas'] ?? 0}', 'Rs. ${e.total}']).toList(),
      ),
      pw.SizedBox(height: 28),
      pw.Text('Thank you.'),
    ]));
    await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: 'Milk_Bill_${customer.name.replaceAll(' ', '_')}_${monthKey(month)}.pdf');
  }

  Future<void> _deleteEntry(MilkEntry entry) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete entry?'), content: Text('Delete the ${entry.date} entry for ${entry.customerName}?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
    if (yes != true) return;
    setState(() => entries.removeWhere((e) => e.id == entry.id));
    await _save();
  }

  @override
  void dispose() {
    for (final c in quantityControllers.values) { c.dispose(); }
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final pages = [_dashboard(), _customersPage(), _entriesPage(), _billsPage()];
    return Scaffold(
      appBar: AppBar(title: const Text('Milk Ledger'), actions: [if (tab == 1) IconButton(onPressed: () => _addCustomer(), icon: const Icon(Icons.person_add_alt_1))]),
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (index) => setState(() => tab = index), destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Customers'),
        NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Entries'),
        NavigationDestination(icon: Icon(Icons.summarize_outlined), selectedIcon: Icon(Icons.summarize), label: 'Monthly Bill'),
      ]),
    );
  }

  Widget _dashboard() {
    final now = DateTime.now();
    final monthEntries = entries.where((e) => e.date.startsWith(monthKey(now))).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [Color(0xFF1557A6), Color(0xFF2686D8)])), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your milk business, organised.', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(DateFormat('EEEE, d MMMM yyyy').format(now), style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 18),
        Text('This month sales', style: TextStyle(color: Colors.white.withOpacity(.85))),
        Text(money(_billTotal(monthEntries)), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
      ])),
      const SizedBox(height: 16),
      Row(children: [Expanded(child: _statCard('Customers', '${customers.length}', Icons.people_alt_outlined)), const SizedBox(width: 12), Expanded(child: _statCard('Entries this month', '${monthEntries.length}', Icons.calendar_month_outlined))]),
      const SizedBox(height: 22),
      const Text('New daily entry', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [const Expanded(child: Text('Customer', style: TextStyle(fontWeight: FontWeight.w600))), TextButton.icon(onPressed: () => _addCustomer(), icon: const Icon(Icons.add), label: const Text('Add'))]),
        DropdownButtonFormField<String>(value: customers.any((c) => c.id == selectedCustomerId) ? selectedCustomerId : null, isExpanded: true, hint: const Text('Select saved customer'), decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)), items: customers.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(), onChanged: (v) => setState(() => selectedCustomerId = v)),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_today), label: Text('Entry date: ${DateFormat('d MMM yyyy').format(entryDate)}')),
        const SizedBox(height: 12),
        for (final item in products.entries) ...[
          TextField(controller: quantityControllers[item.key], keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: '${item.key} · ${money(item.value)} per packet', border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.shopping_bag_outlined))),
          const SizedBox(height: 10),
        ],
        TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.notes))),
        const SizedBox(height: 14),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(14)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Entry total', style: TextStyle(fontWeight: FontWeight.bold)), Text(money(draftTotal), style: const TextStyle(fontSize: 22, color: Color(0xFF1557A6), fontWeight: FontWeight.bold))])),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: _saveEntry, icon: const Icon(Icons.save_outlined), label: const Text('Save daily entry'), style: FilledButton.styleFrom(padding: const EdgeInsets.all(15))),
      ]))),
      const SizedBox(height: 20),
      const Text('Product rates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      ...products.entries.map((p) => Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.local_drink_outlined)), title: Text(p.key), trailing: Text('${money(p.value)} / packet', style: const TextStyle(fontWeight: FontWeight.bold))))),
    ]);
  }

  Widget _statCard(String label, String value, IconData icon) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: const Color(0xFF1557A6)), const SizedBox(height: 10), Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(color: Colors.black54))])));

  Widget _customersPage() => customers.isEmpty
      ? _emptyState(Icons.people_outline, 'No customers yet', 'Add each customer once. Then select their name from the dropdown for every entry.', FilledButton.icon(onPressed: () => _addCustomer(), icon: const Icon(Icons.person_add), label: const Text('Add customer')))
      : ListView(padding: const EdgeInsets.all(12), children: [FilledButton.icon(onPressed: () => _addCustomer(), icon: const Icon(Icons.person_add_alt_1), label: const Text('Add customer')), const SizedBox(height: 8), ...customers.map((c) => Card(child: ListTile(leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())), title: Text(c.name), subtitle: Text(c.phone.isEmpty ? 'No phone added' : c.phone), onTap: () => setState(() { selectedCustomerId = c.id; tab = 0; }), trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'edit') _addCustomer(editing: c); if (v == 'delete') _deleteCustomer(c); }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))])))]);

  Widget _entriesPage() {
    final sorted = entries.toList()..sort((a, b) => b.date.compareTo(a.date));
    if (sorted.isEmpty) {
      return _emptyState(
        Icons.receipt_long_outlined,
        'No entries yet',
        'Daily entries will appear here after you save them.',
        FilledButton(
          onPressed: () => setState(() => tab = 0),
          child: const Text('Create entry'),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.all(12), children: [Text('${entries.length} saved entries', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8), ...sorted.map((e) => Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.local_drink_outlined)), title: Text(e.customerName), subtitle: Text('${e.date}  •  Taaza ${e.quantities['Amul Taaza'] ?? 0}, Gold ${e.quantities['Amul Gold'] ?? 0}, Chaas ${e.quantities['Chaas'] ?? 0}${e.note.isEmpty ? '' : '\n${e.note}'}'), isThreeLine: e.note.isNotEmpty, trailing: SizedBox(width: 82, child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(money(e.total), style: const TextStyle(fontWeight: FontWeight.bold)), PopupMenuButton<String>(padding: EdgeInsets.zero, onSelected: (v) { if (v == 'delete') _deleteEntry(e); }, itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete entry'))])]))))]);
  }

  Widget _billsPage() => _BillsView(
        customers: customers,
        entriesFor: _customerMonthEntries,
        totalFor: _billTotal,
        quantityFor: _billQuantity,
        exportBill: _exportBill,
      );

  Widget _emptyState(IconData icon, String title, String subtitle, Widget action) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 58, color: Colors.blueGrey), const SizedBox(height: 16), Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)), const SizedBox(height: 18), action])));
}

class _BillsView extends StatefulWidget {
  final List<Customer> customers;
  final List<MilkEntry> Function(String, DateTime) entriesFor;
  final int Function(List<MilkEntry>) totalFor;
  final int Function(List<MilkEntry>, String) quantityFor;
  final Future<void> Function(Customer, DateTime) exportBill;
  const _BillsView({required this.customers, required this.entriesFor, required this.totalFor, required this.quantityFor, required this.exportBill});
  @override
  State<_BillsView> createState() => _BillsViewState();
}

class _BillsViewState extends State<_BillsView> {
  String? customerId;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  @override
  Widget build(BuildContext context) {
    if (widget.customers.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Add customers and save entries to generate monthly bills.', textAlign: TextAlign.center)));
    customerId ??= widget.customers.first.id;
    if (!widget.customers.any((c) => c.id == customerId)) customerId = widget.customers.first.id;
    final customer = widget.customers.firstWhere((c) => c.id == customerId);
    final list = widget.entriesFor(customer.id, month);
    final total = widget.totalFor(list);
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Monthly customer bill', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(value: customerId, isExpanded: true, decoration: const InputDecoration(labelText: 'Customer', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)), items: widget.customers.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(), onChanged: (v) => setState(() => customerId = v)),
      const SizedBox(height: 12),
      Card(child: ListTile(leading: const Icon(Icons.calendar_month), title: Text(DateFormat('MMMM yyyy').format(month)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left)), IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right))]))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(customer.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)), if (customer.phone.isNotEmpty) Text(customer.phone), Text(DateFormat('MMMM yyyy').format(month), style: const TextStyle(color: Colors.black54)), const Divider(height: 28), ...products.entries.map((p) { final qty = widget.quantityFor(list, p.key); return Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [Expanded(child: Text(p.key)), Text('$qty × ${money(p.value)}'), const SizedBox(width: 16), SizedBox(width: 75, child: Text(money(qty * p.value), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)))])); }), const Divider(height: 28), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL DUE', style: TextStyle(fontWeight: FontWeight.bold)), Text(money(total), style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold, color: Color(0xFF1557A6)))]), Text('${list.length} daily entries', style: const TextStyle(color: Colors.black54)), const SizedBox(height: 16), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => widget.exportBill(customer, month), icon: const Icon(Icons.picture_as_pdf), label: const Text('Generate / Share PDF bill')))])),
      const SizedBox(height: 18),
      const Text('Daily details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (list.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No entries for this customer in this month.'))),
      ...list.map((e) => Card(child: ListTile(title: Text(DateFormat('d MMM yyyy').format(DateTime.parse(e.date))), subtitle: Text('Taaza ${e.quantities['Amul Taaza'] ?? 0} • Gold ${e.quantities['Amul Gold'] ?? 0} • Chaas ${e.quantities['Chaas'] ?? 0}'), trailing: Text(money(e.total), style: const TextStyle(fontWeight: FontWeight.bold))))),
    ]);
  }
}
