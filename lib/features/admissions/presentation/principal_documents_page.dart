import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/admission_approval_repository.dart';

/// Principal certificate review. The server checks the Principal role for
/// every metadata, short-lived link and document decision request.
class PrincipalDocumentsPage extends StatefulWidget {
  const PrincipalDocumentsPage({
    super.key,
    required this.applicationId,
    required this.repository,
  });
  final String applicationId;
  final AdmissionApprovalRepository repository;

  @override
  State<PrincipalDocumentsPage> createState() => _PrincipalDocumentsPageState();
}

class _PrincipalDocumentsPageState extends State<PrincipalDocumentsPage> {
  bool _loading = false;
  String? _error;
  String? _busyId;
  List<PrincipalDocumentRecord> _documents = const [];
  final Set<String> _opened = {};
  final Map<String,String> _operations = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    setState(() { _loading=true; _error=null; _documents=const []; });
    try {
      final records = await widget.repository.listDocuments(
        widget.applicationId);
      if (!mounted) return;
      setState(() { _loading=false; _documents=records; });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading=false;
        _error='Cannot load authorized certificate information.';
      });
    }
  }

  Future<void> _inspect(PrincipalDocumentRecord document) async {
    if (_busyId!=null) return;
    setState(() { _busyId=document.id; _error=null; });
    try {
      final url=await widget.repository.signedDocumentUrl(document);
      final uri=Uri.parse(url);
      if (uri.scheme!='https') {
        throw StateError('Document link must be secure');
      }
      final opened=await launchUrl(uri,mode:LaunchMode.externalApplication);
      if (!opened) throw StateError('Could not open private certificate');
      if (!mounted) return;
      setState(() => _opened.add(document.id));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error='Unable to open private certificate. '
        'Check network, app permissions and available PDF/image viewer.');
    } finally {
      if (mounted) setState(() => _busyId=null);
    }
  }

  Future<void> _decide(PrincipalDocumentRecord document,
      String decision) async {
    if (_busyId!=null || !_opened.contains(document.id)) return;
    final reason=TextEditingController();
    final answer=await showDialog<String>(
      context:context,
      builder:(dialogContext)=>AlertDialog(
        title:Text(decision=='verify'
          ? 'Verify inspected certificate?'
          : 'Reject inspected certificate?'),
        content:Column(mainAxisSize:MainAxisSize.min,
          crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Document: ${document.kind}. File version: '
            '${document.version ?? 0}.'),
          const SizedBox(height:8),
          const Text('Confirm that you inspected this exact private file. '
            'Verification is an accountable Principal action.'),
          if(decision=='reject') ...[
            const SizedBox(height:10),
            TextField(controller:reason,maxLines:3,
              key:const Key('document-rejection-reason'),
              decoration:const InputDecoration(
                labelText:'Rejection reason (required)')),
          ],
        ]),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialogContext),
            child:const Text('Cancel')),
          FilledButton(
            key:const Key('confirm-document-review'),
            onPressed:(){
              if(decision=='reject' && reason.text.trim().length<4) return;
              Navigator.pop(dialogContext,
                decision=='verify' ? '' : reason.text.trim());
            },
            child:Text(decision=='verify'?'Verify':'Reject'),
          ),
        ],
      ),
    );
    reason.dispose();
    if(answer==null || !mounted) return;
    final key='${document.id}:${document.revision}:$decision';
    final operation=_operations.putIfAbsent(
      key,SupabaseAdmissionApprovalRepository.operationUuid);
    setState(() { _busyId=document.id; _error=null; });
    try {
      await widget.repository.reviewDocument(
        documentId:document.id,expectedRevision:document.revision,
        operationId:operation,decision:decision,
        reason:answer.isEmpty?null:answer,
      );
      if (!mounted) return;
      _operations.remove(key);
      _opened.remove(document.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text(decision=='verify'
          ? 'Document verified and audited.'
          : 'Document rejected with recorded reason.'),
      ));
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error='Document decision not confirmed. '
        'Retry the same operation; no duplicate review will be created.');
    } finally {
      if(mounted) setState(()=>_busyId=null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title:const Text('Principal • Certificate Review')),
    body:ListView(
      key:const Key('principal-document-review-page'),
      padding:const EdgeInsets.all(18),
      children:[
        const Card(child:Padding(
          padding:EdgeInsets.all(12),
          child:Text('Only registered private certificates may be opened. '
            'Preview links expire after 60 seconds. A certificate is not '
            'verified merely because it was uploaded.'),
        )),
        if(_loading) const LinearProgressIndicator(),
        if(_error!=null)
          ListTile(leading:const Icon(Icons.error_outline),
            title:Text(_error!),
            trailing:TextButton(onPressed:_refresh,
              child:const Text('Retry'))),
        if(!_loading && _error==null) ...[
          if(_documents.isEmpty)
            const ListTile(title:Text('No certificate requirements'))
          else
            for(final document in _documents)
              if(document.applicable)
                Card.outlined(child:Padding(
                  padding:const EdgeInsets.all(12),
                  child:Column(
                    crossAxisAlignment:CrossAxisAlignment.start,
                    children:[
                      Text(document.kind,
                        style:Theme.of(context).textTheme.titleMedium),
                      Text('Status: ${document.status.toUpperCase()} • '
                        'Revision ${document.revision} • '
                        'File version ${document.version ?? 0}'),
                      const SizedBox(height:10),
                      Wrap(spacing:8,runSpacing:8,children:[
                        OutlinedButton.icon(
                          key:Key('inspect-document-${document.id}'),
                          onPressed:_busyId==null && document.canInspect
                            ? ()=>_inspect(document):null,
                          icon:const Icon(Icons.open_in_new),
                          label:const Text('Inspect file'),
                        ),
                        FilledButton(
                          key:Key('verify-document-${document.id}'),
                          onPressed:_busyId==null &&
                            _opened.contains(document.id) &&
                            document.canInspect
                            ? ()=>_decide(document,'verify'):null,
                          child:const Text('Verify'),
                        ),
                        OutlinedButton(
                          key:Key('reject-document-${document.id}'),
                          onPressed:_busyId==null &&
                            _opened.contains(document.id) &&
                            document.canInspect
                            ? ()=>_decide(document,'reject'):null,
                          child:const Text('Reject'),
                        ),
                      ]),
                    ]),
                )),
        ],
      ],
    ),
  );
}
