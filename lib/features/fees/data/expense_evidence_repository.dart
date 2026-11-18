import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// An immutable reference to a private expense invoice or payment receipt.
class ExpenseEvidence {
  const ExpenseEvidence({
    required this.id,required this.kind,required this.path,
    required this.fileName,required this.status,required this.bytes,
    required this.uploadedAt,this.paymentId,this.rejectionReason,
  });
  final String id,kind,path,fileName,status,uploadedAt;
  final String? paymentId,rejectionReason;
  final int bytes;

  factory ExpenseEvidence.fromJson(Map<String,dynamic> x)=>ExpenseEvidence(
    id:x['id'] as String,kind:x['kind'] as String,
    path:x['path'] as String,fileName:x['file_name'] as String,
    status:x['status'] as String,bytes:(x['bytes'] as num).toInt(),
    uploadedAt:x['uploaded_at'].toString(),
    paymentId:x['payment_id'] as String?,
    rejectionReason:x['rejection_reason'] as String?);
}

class ExpenseEvidenceWorkspace {
  const ExpenseEvidenceWorkspace({required this.isOwner,
    required this.requestStatus,required this.canUploadInvoice,
    required this.canUploadReceipt,required this.attachments});
  final bool isOwner,canUploadInvoice,canUploadReceipt;
  final String requestStatus;
  final List<ExpenseEvidence> attachments;

  factory ExpenseEvidenceWorkspace.fromJson(Map<String,dynamic> x)=>
    ExpenseEvidenceWorkspace(
      isOwner:x['is_owner']==true,requestStatus:x['request_status'] as String,
      canUploadInvoice:x['can_upload_invoice']==true,
      canUploadReceipt:x['can_upload_receipt']==true,
      attachments:List.unmodifiable([
        for(final row in (x['attachments'] as List? ?? const []))
          ExpenseEvidence.fromJson(Map<String,dynamic>.from(row as Map))]));
}

abstract class ExpenseEvidenceRepository {
  const ExpenseEvidenceRepository();
  Future<ExpenseEvidenceWorkspace> list({
    required String schoolId,required String campusId,required String requestId});
  /// Returns false if the user cancels file selection; true only after DB registration.
  Future<bool> pickAndUpload({
    required String schoolId,required String campusId,required String requestId,
    required String kind,String? paymentId});
  Future<void> review({
    required String schoolId,required String campusId,required String attachmentId,
    required String decision,String? reason});
  /// Short-lived preview URL. No public bucket or permanent URLs.
  Future<String> signedPreview(ExpenseEvidence attachment);
}

class ExpenseEvidenceValidator {
  static const maxBytes=10485760;
  static String? mime(String ext)=>switch(ext){
    'pdf'=>'application/pdf','jpg'=>'image/jpeg',
    'png'=>'image/png','webp'=>'image/webp',_=>null};
  static bool validBytes(Uint8List bytes,String extension){
    if(bytes.isEmpty||bytes.length>maxBytes)return false;
    if(extension=='pdf')return bytes.length>=5&&
      bytes[0]==0x25&&bytes[1]==0x50&&bytes[2]==0x44&&
      bytes[3]==0x46&&bytes[4]==0x2d;
    if(extension=='jpg')return bytes.length>=3&&
      bytes[0]==0xff&&bytes[1]==0xd8&&bytes[2]==0xff;
    if(extension=='png')return bytes.length>=8&&
      bytes[0]==0x89&&bytes[1]==0x50&&bytes[2]==0x4e&&
      bytes[3]==0x47&&bytes[4]==0x0d&&bytes[5]==0x0a;
    if(extension=='webp')return bytes.length>=12&&
      bytes[0]==0x52&&bytes[1]==0x49&&bytes[2]==0x46&&
      bytes[3]==0x46&&bytes[8]==0x57&&bytes[9]==0x45&&
      bytes[10]==0x42&&bytes[11]==0x50;
    return false;
  }
}

class SupabaseExpenseEvidenceRepository implements ExpenseEvidenceRepository {
  SupabaseExpenseEvidenceRepository(this.client);
  final SupabaseClient client;
  static const bucket='sms-expense-evidence';
  // A successful binary upload but failed RPC must retry registration, not
  // generate a second file. The key includes the payment target.
  final Map<String,({String path,String name})> _pending={};
  static String _uuid(){
    final random=Random.secure();
    final b=List<int>.generate(16,(_)=>random.nextInt(256));
    b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;
    final h=b.map((e)=>e.toRadixString(16).padLeft(2,'0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-'
      '${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }
  void _requireAuth(){
    if(client.auth.currentSession==null){
      throw StateError('Expense evidence requires a signed-in account');
    }
  }
  Future<Map<String,dynamic>> _rpc(String name,Map<String,Object?> params)async{
    _requireAuth();
    final response=await client.rpc(name,params:params);
    if(response is! Map)throw StateError('Invalid evidence server response');
    return Map<String,dynamic>.from(response);
  }
  @override
  Future<ExpenseEvidenceWorkspace> list({required String schoolId,
    required String campusId,required String requestId})async{
    final response=await _rpc('expense_evidence_list',{
      'p_school':schoolId,'p_campus':campusId,'p_request':requestId});
    return ExpenseEvidenceWorkspace.fromJson(response);
  }
  Future<void> _register({required String schoolId,required String campusId,
    required String requestId,required String kind,String? paymentId,
    required String path,required String fileName})async{
    final result=await _rpc('expense_evidence_register',{
      'p_school':schoolId,'p_campus':campusId,'p_request':requestId,
      'p_payment':paymentId,'p_kind':kind,'p_path':path,
      'p_file_name':fileName});
    if(result['saved']!=true||result['attachment_id'] is! String){
      throw StateError('Evidence registration was not confirmed');
    }
  }
  @override
  Future<bool> pickAndUpload({required String schoolId,required String campusId,
    required String requestId,required String kind,String? paymentId})async{
    _requireAuth();
    if(!((kind=='invoice'&&paymentId==null)||
         (kind=='receipt'&&paymentId!=null))){
      throw const FormatException('Receipt must target an actual payment');
    }
    final key='$schoolId/$campusId/$requestId/$kind/${paymentId??'request'}';
    final retry=_pending[key];
    if(retry!=null){
      await _register(schoolId:schoolId,campusId:campusId,
        requestId:requestId,kind:kind,paymentId:paymentId,
        path:retry.path,fileName:retry.name);
      _pending.remove(key);
      return true;
    }
    final selection=await FilePicker.pickFiles(type:FileType.custom,
      allowedExtensions:const ['pdf','jpg','jpeg','png','webp'],
      withData:true,allowMultiple:false);
    if(selection==null||selection.files.isEmpty)return false;
    final file=selection.files.single;
    final ext=file.extension?.toLowerCase()=='jpeg'
      ?'jpg':file.extension?.toLowerCase();
    final bytes=file.bytes;
    if(bytes==null||ext==null||ExpenseEvidenceValidator.mime(ext)==null||
      !ExpenseEvidenceValidator.validBytes(bytes,ext)){
      throw const FormatException('Use a valid PDF/JPG/PNG/WebP file up to 10 MiB');
    }
    final name=file.name.trim();
    if(name.isEmpty||name.length>180){
      throw const FormatException('Evidence filename must be 1–180 characters');
    }
    final path='$schoolId/$campusId/$requestId/${paymentId??'request'}/${_uuid()}.$ext';
    await client.storage.from(bucket).uploadBinary(path,bytes,
      fileOptions:FileOptions(contentType:ExpenseEvidenceValidator.mime(ext),
        upsert:false,cacheControl:'0'));
    _pending[key]=(path:path,name:name);
    await _register(schoolId:schoolId,campusId:campusId,
      requestId:requestId,kind:kind,paymentId:paymentId,
      path:path,fileName:name);
    _pending.remove(key);
    return true;
  }
  @override
  Future<void> review({required String schoolId,required String campusId,
    required String attachmentId,required String decision,String? reason})async{
    if(!{'verified','rejected'}.contains(decision)){
      throw const FormatException('Invalid evidence decision');
    }
    final result=await _rpc('expense_evidence_review',{
      'p_school':schoolId,'p_campus':campusId,
      'p_attachment':attachmentId,'p_decision':decision,
      'p_reason':decision=='rejected'?reason:null});
    if(result['saved']!=true||result['attachment_id']!=attachmentId||
       result['status']!=decision){
      throw StateError('Evidence verification was not confirmed');
    }
  }
  @override
  Future<String> signedPreview(ExpenseEvidence attachment)async{
    _requireAuth();
    if(!attachment.path.contains('/')){
      throw const FormatException('Invalid evidence path');
    }
    return client.storage.from(bucket).createSignedUrl(attachment.path,90);
  }
}
