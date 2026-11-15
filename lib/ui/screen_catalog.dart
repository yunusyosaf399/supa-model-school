/// UI-only screen catalog for the Supa Model School design preview.
/// All data shown through the preview is fictional, never persisted.
enum PreviewLayout {
  overview,
  table,
  form,
  payment,
  attendance,
  closing,
  approvals,
  sync,
  slip,
  settings,
}

class ScreenSpec {
  const ScreenSpec(
    this.title,
    this.layout, {
    this.description = '',
    this.fields = const <String>[],
    this.columns = const <String>[],
    this.later = false,
  });

  final String title;
  final PreviewLayout layout;
  final String description;
  final List<String> fields;
  final List<String> columns;
  final bool later;
}

const schoolScreenCatalog = <String, List<ScreenSpec>>{
  'Dashboard': [
    ScreenSpec('Campus Overview', PreviewLayout.overview, description: 'Today: collections, pending fees, attendance and tasks.'),
    ScreenSpec('Owner Overview', PreviewLayout.overview, description: 'Consolidated totals and authorized campus comparisons.'),
    ScreenSpec('Notifications & Tasks', PreviewLayout.table, columns: ['Priority', 'Task', 'Campus', 'Status']),
  ],
  'Students': [
    ScreenSpec('Student Directory', PreviewLayout.table, description: 'Real Flutter demo directory is available separately.', columns: ['Student', 'Registration', 'Class', 'Status']),
    ScreenSpec('Student Profile', PreviewLayout.overview, description: 'Personal, guardian, academic, fees, attendance and document tabs.'),
    ScreenSpec('Enrollment History', PreviewLayout.table, columns: ['Year', 'Campus', 'Class', 'Section', 'Status']),
    ScreenSpec('Promotions', PreviewLayout.form, fields: ['Academic year', 'From class', 'To class', 'Effective date', 'Reason']),
    ScreenSpec('Campus Transfer', PreviewLayout.form, fields: ['Student', 'Source campus', 'Destination campus', 'Transfer date', 'Outstanding dues', 'Reason']),
    ScreenSpec('Student Documents', PreviewLayout.table, columns: ['Document', 'Required', 'Status', 'Deadline', 'Verified by']),
  ],
  'Admissions': [
    ScreenSpec('Admissions Inbox', PreviewLayout.table, columns: ['Application', 'Student', 'Campus', 'Documents', 'Approval']),
    ScreenSpec('Six-Step Admission', PreviewLayout.form, description: 'Open the existing complete Flutter wizard from the button.', fields: ['Student details', 'Guardians', 'Academic placement', 'Documents', 'Fee setup', 'Review']),
    ScreenSpec('Principal Review', PreviewLayout.approvals, description: 'Approve or return an admission if the Owner enabled approval.'),
    ScreenSpec('Missing Documents', PreviewLayout.table, columns: ['Student', 'Document', 'Deadline', 'Days left', 'Status']),
    ScreenSpec('Admission Settings', PreviewLayout.settings, fields: ['Principal approval required', 'Conditional admission', 'Default document deadline']),
  ],
  'Fees': [
    ScreenSpec('Fee Overview', PreviewLayout.overview, description: 'Monthly collection, arrears, credits and category breakdown.'),
    ScreenSpec('Collect Fee', PreviewLayout.payment, description: 'Partial and advance allocation preview; no real receipt is issued.'),
    ScreenSpec('Student Fee Ledger', PreviewLayout.table, columns: ['Month', 'Category', 'Original', 'Discount', 'Paid', 'Due']),
    ScreenSpec('Monthly Fee Generation', PreviewLayout.form, fields: ['Campus', 'Academic year', 'Billing month', 'Class', 'Categories']),
    ScreenSpec('Class Fee Plans', PreviewLayout.table, columns: ['Class', 'Tuition', 'Exam', 'Uniform', 'Effective date']),
    ScreenSpec('Student Fee Settings', PreviewLayout.form, fields: ['Student', 'Monthly transport amount', 'Admission fee', 'Effective from']),
    ScreenSpec('Discounts & Waivers', PreviewLayout.form, fields: ['Student', 'Fee category', 'Discount type', 'Discount amount', 'Reason']),
    ScreenSpec('Advance Credits', PreviewLayout.table, columns: ['Student', 'Receipt', 'Advance received', 'Allocated', 'Remaining']),
    ScreenSpec('Fee Receipts & Slips', PreviewLayout.slip, description: 'Receipt and month-wise fee slip printing layout.'),
  ],
  'Attendance': [
    ScreenSpec('Daily Student Register', PreviewLayout.attendance, description: 'Present, Absent, Leave, Late; complete register before submission.'),
    ScreenSpec('Staff Attendance', PreviewLayout.attendance, description: 'Daily status and optional check-in/out.'),
    ScreenSpec('Daily Absentees', PreviewLayout.table, columns: ['Student', 'Class', 'Status', 'Date', 'Remarks']),
    ScreenSpec('Monthly Attendance', PreviewLayout.table, columns: ['Name', 'Present', 'Late', 'Absent', 'Leave', 'Rate']),
    ScreenSpec('Attendance Corrections', PreviewLayout.form, fields: ['Student / staff', 'Original status', 'Corrected status', 'Date', 'Mandatory reason']),
    ScreenSpec('Attendance Calendar', PreviewLayout.settings, fields: ['Working days', 'School holiday', 'Campus closure', 'Remarks']),
  ],
  'Employees': [
    ScreenSpec('Employee Directory', PreviewLayout.table, columns: ['Employee ID', 'Name', 'Role', 'Campus', 'Status']),
    ScreenSpec('New Employee', PreviewLayout.form, fields: ['Name', 'CNIC / ID', 'Mobile number', 'Designation', 'Primary campus', 'Joining date']),
    ScreenSpec('Employee Profile', PreviewLayout.overview, description: 'Employee records, attendance, advances and salary history.'),
    ScreenSpec('Temporary Assignment', PreviewLayout.form, fields: ['Employee', 'Primary campus', 'Temporary campus', 'Start date', 'End date']),
  ],
  'Payroll': [
    ScreenSpec('Payroll Overview', PreviewLayout.overview, description: 'Monthly salary due, paid and pending approvals.'),
    ScreenSpec('Generate Payroll', PreviewLayout.form, fields: ['Campus', 'Salary month', 'Eligible employees', 'Approval policy']),
    ScreenSpec('Payroll Register', PreviewLayout.table, columns: ['Employee', 'Gross', 'Deductions', 'Advance recovery', 'Net', 'Status']),
    ScreenSpec('Allowances & Deductions', PreviewLayout.form, fields: ['Employee', 'Period', 'Adjustment type', 'Amount', 'Reason']),
    ScreenSpec('Salary Advances', PreviewLayout.form, fields: ['Employee', 'Advance amount', 'Issue date', 'Recovery type', 'Monthly recovery']),
    ScreenSpec('Pay Salary', PreviewLayout.payment, description: 'Full and partial salary payment design; offline approval rules apply.'),
    ScreenSpec('Salary Slips', PreviewLayout.slip),
    ScreenSpec('Salary Payment History', PreviewLayout.table, columns: ['Date', 'Employee', 'Payroll month', 'Paid', 'Method', 'Status']),
  ],
  'Expenses': [
    ScreenSpec('Expense Overview', PreviewLayout.overview),
    ScreenSpec('Record Expense', PreviewLayout.form, fields: ['Campus', 'Expense category', 'Amount', 'Date', 'Cash / bank', 'Description', 'Receipt reference']),
    ScreenSpec('Expense Register', PreviewLayout.table, columns: ['Date', 'Category', 'Amount', 'Account', 'Approval', 'Reference']),
    ScreenSpec('Expense Categories', PreviewLayout.settings, fields: ['Category name', 'Campus availability', 'Requires approval']),
    ScreenSpec('Medical & Examination Costs', PreviewLayout.form, fields: ['Expense type', 'Student / exam reference', 'Date', 'Amount', 'Notes']),
  ],
  'Finance': [
    ScreenSpec('Financial Overview', PreviewLayout.overview),
    ScreenSpec('Daily Cashbook', PreviewLayout.table, columns: ['Time', 'Reference', 'Money in', 'Money out', 'Account', 'Status']),
    ScreenSpec('Daily Cash Closing', PreviewLayout.closing, description: 'Provisional until pending offline events and conflicts are resolved.'),
    ScreenSpec('Cash & Bank Accounts', PreviewLayout.table, columns: ['Account', 'Campus', 'Opening', 'Balance', 'Status']),
    ScreenSpec('Account Transfer', PreviewLayout.form, fields: ['From account', 'To account', 'Amount', 'Transfer date', 'Reference', 'Reason']),
    ScreenSpec('Other Income', PreviewLayout.form, fields: ['Income category', 'Date', 'Amount', 'Cash / bank', 'Description']),
    ScreenSpec('Owner Investments', PreviewLayout.form, fields: ['Owner', 'Campus', 'Investment amount', 'Date', 'Bank / cash', 'Narration']),
    ScreenSpec('Principal Cash Transfers', PreviewLayout.form, fields: ['From account', 'Principal', 'Amount', 'Date', 'Acknowledgement']),
    ScreenSpec('Transaction History', PreviewLayout.table, columns: ['Reference', 'Date', 'Type', 'Amount', 'Campus', 'Status']),
  ],
  'Canteen': [
    ScreenSpec('Canteen Overview', PreviewLayout.overview),
    ScreenSpec('Products', PreviewLayout.table, columns: ['SKU', 'Product', 'Cost', 'Selling price', 'Stock']),
    ScreenSpec('Purchases & Stock In', PreviewLayout.form, fields: ['Product', 'Supplier', 'Quantity', 'Unit cost', 'Purchase date']),
    ScreenSpec('Daily Sales', PreviewLayout.form, fields: ['Sales date', 'Sales mode', 'Product / daily total', 'Quantity', 'Cash / bank']),
    ScreenSpec('Stock Movements', PreviewLayout.table, columns: ['Date', 'Product', 'In', 'Out', 'Balance']),
    ScreenSpec('Canteen Profit Summary', PreviewLayout.overview),
  ],
  'Uniforms': [
    ScreenSpec('Uniform Overview', PreviewLayout.overview),
    ScreenSpec('Cloth & Materials', PreviewLayout.table, columns: ['Material', 'Unit', 'Purchased', 'Consumed', 'Available']),
    ScreenSpec('Material Purchases', PreviewLayout.form, fields: ['Material', 'Supplier', 'Quantity', 'Unit price', 'Date']),
    ScreenSpec('Tailoring & Wages', PreviewLayout.form, fields: ['Tailor', 'Batch', 'Units', 'Wages', 'Date']),
    ScreenSpec('Production Batches', PreviewLayout.form, fields: ['Uniform type', 'Size', 'Quantity', 'Cloth used', 'Tailor', 'Completion date']),
    ScreenSpec('Uniform Stock & Sales', PreviewLayout.table, columns: ['Product', 'Size', 'Produced', 'Sold', 'Remaining']),
    ScreenSpec('Uniform Costing Analysis', PreviewLayout.overview, later: true),
  ],
  'Vehicles': [
    ScreenSpec('Vehicle Directory', PreviewLayout.table, columns: ['Vehicle', 'Plate', 'Campus', 'Driver', 'Status']),
    ScreenSpec('Driver Details', PreviewLayout.table, columns: ['Employee', 'License', 'Vehicle', 'Primary campus']),
    ScreenSpec('Fuel Expense', PreviewLayout.form, fields: ['Vehicle', 'Date', 'Litres', 'Fuel cost', 'Odometer']),
    ScreenSpec('Maintenance Expense', PreviewLayout.form, fields: ['Vehicle', 'Service', 'Date', 'Expense amount', 'Next service']),
  ],
  'Approvals': [
    ScreenSpec('Pending Approvals', PreviewLayout.approvals),
    ScreenSpec('Approval Review', PreviewLayout.approvals, description: 'Review original values, proposed action and audit impact.'),
    ScreenSpec('Correction Requests', PreviewLayout.table, columns: ['Record', 'Requested by', 'Reason', 'Difference', 'Status']),
    ScreenSpec('Approval History', PreviewLayout.table, columns: ['When', 'Action', 'Approver', 'Decision', 'Reason']),
  ],
  'Reports': [
    ScreenSpec('Reports Center', PreviewLayout.overview),
    ScreenSpec('Student Reports', PreviewLayout.table, columns: ['Class', 'Active', 'New', 'Transferred', 'Withdrawn']),
    ScreenSpec('Fee Collection Report', PreviewLayout.table, columns: ['Period', 'Tuition', 'Transport', 'Other', 'Collected', 'Due']),
    ScreenSpec('Outstanding Dues Report', PreviewLayout.table, columns: ['Student', 'Month', 'Category', 'Outstanding']),
    ScreenSpec('Attendance Report', PreviewLayout.table, columns: ['Class', 'Eligible days', 'Attended', 'Rate']),
    ScreenSpec('Payroll Report', PreviewLayout.table, columns: ['Campus', 'Gross', 'Recovered', 'Paid', 'Unpaid']),
    ScreenSpec('Expense Report', PreviewLayout.table, columns: ['Category', 'Cash', 'Bank', 'Total']),
    ScreenSpec('Cash & Bank Report', PreviewLayout.table, columns: ['Account', 'Opening', 'In', 'Out', 'Closing']),
    ScreenSpec('Canteen & Uniform Report', PreviewLayout.table, columns: ['Business', 'Sales', 'Cost', 'Operating result']),
    ScreenSpec('Owner Campus Comparison', PreviewLayout.overview),
    ScreenSpec('Audit Report', PreviewLayout.table, columns: ['When', 'User', 'Module', 'Action', 'Record']),
  ],
  'Sync Center': [
    ScreenSpec('Synchronization Overview', PreviewLayout.sync),
    ScreenSpec('Pending Uploads', PreviewLayout.table, columns: ['Operation ID', 'Module', 'Created', 'Status', 'Retries']),
    ScreenSpec('Conflict Review', PreviewLayout.approvals, description: 'Suspected duplicate payments remain unresolved for human review.'),
    ScreenSpec('Synchronization History', PreviewLayout.table, columns: ['Date', 'Uploaded', 'Downloaded', 'Conflicts', 'Status']),
    ScreenSpec('Backup & Recovery', PreviewLayout.sync),
    ScreenSpec('Backup History', PreviewLayout.table, columns: ['When', 'Destination', 'Checksum', 'Verification', 'Status']),
  ],
  'Settings': [
    ScreenSpec('School Profile', PreviewLayout.settings, fields: ['School name', 'School code', 'Address', 'Logo', 'Currency', 'Timezone']),
    ScreenSpec('Campuses', PreviewLayout.table, columns: ['Campus', 'Code', 'Address', 'Status']),
    ScreenSpec('Academic Years', PreviewLayout.table, columns: ['Year', 'Start date', 'End date', 'Active']),
    ScreenSpec('Classes & Sections', PreviewLayout.table, columns: ['Campus', 'Class', 'Section', 'Status']),
    ScreenSpec('Users & Roles', PreviewLayout.table, columns: ['User', 'Role', 'Campus scope', 'Status']),
    ScreenSpec('Permissions Matrix', PreviewLayout.settings, fields: ['Role', 'Permission group', 'View', 'Create', 'Edit', 'Approve']),
    ScreenSpec('Approval Policies', PreviewLayout.settings, fields: ['Expense threshold', 'Principal admission approval', 'Payroll approval role']),
    ScreenSpec('Fee Policies', PreviewLayout.settings, fields: ['Auto fee generation', 'Billing date', 'Advance allocation', 'Discount scope']),
    ScreenSpec('Payroll Policies', PreviewLayout.settings, fields: ['Monthly salary', 'Advance recovery', 'Allow partial payment', 'Approval role']),
    ScreenSpec('Offline Campus & Devices', PreviewLayout.settings, fields: ['Assigned offline campus', 'Trusted Windows device', 'Sync interval']),
    ScreenSpec('Backup Destinations', PreviewLayout.settings, fields: ['Local backup folder', 'External drive', 'Cloud copy', 'Retention']),
    ScreenSpec('Keyboard Shortcuts', PreviewLayout.settings, fields: ['Global search', 'Students', 'Payments', 'Save form', 'Print']),
    ScreenSpec('Printing & Slips', PreviewLayout.settings, fields: ['School heading', 'Paper size', 'Receipt footer', 'Copies']),
    ScreenSpec('Appearance & Language', PreviewLayout.settings, fields: ['Language', 'Theme', 'Text scale', 'Density']),
    ScreenSpec('Audit & Activity Log', PreviewLayout.table, columns: ['Time', 'User', 'Action', 'Campus', 'Result']),
  ],
  'Search & Print': [
    ScreenSpec('Global Search', PreviewLayout.table, columns: ['Type', 'Record / Action', 'Campus', 'Open']),
    ScreenSpec('Action Command Palette', PreviewLayout.table, columns: ['Command', 'Shortcut', 'Module']),
    ScreenSpec('Receipt Preview', PreviewLayout.slip),
    ScreenSpec('Monthly Fee Slip', PreviewLayout.slip),
    ScreenSpec('Salary Slip Preview', PreviewLayout.slip),
    ScreenSpec('Expense Voucher', PreviewLayout.slip),
    ScreenSpec('Bank / Cash Payment Slip', PreviewLayout.slip),
  ],
  'Authentication': [
    ScreenSpec('Sign In', PreviewLayout.form, fields: ['Email or username', 'Password', 'Campus']),
    ScreenSpec('Forgot Password', PreviewLayout.form, fields: ['Email address']),
    ScreenSpec('Offline Session Status', PreviewLayout.sync, description: 'Only the trusted campus-bound Windows device may access offline records.'),
  ],
  'Examinations (Later)': [
    ScreenSpec('Exam Register', PreviewLayout.table, columns: ['Exam', 'Class', 'Date', 'Status'], later: true),
    ScreenSpec('Student Exam History', PreviewLayout.table, columns: ['Exam', 'Subject', 'Marks', 'Grade'], later: true),
  ],
};
