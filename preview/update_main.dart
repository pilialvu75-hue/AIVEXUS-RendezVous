import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aivexus_original_updater/aivexus_original_updater.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

const repository = 'AIVEXUS-RendezVous';
const manifest = 'https://raw.githubusercontent.com/pilialvu75-hue/$repository/main/update/version.json';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final info = await PackageInfo.fromPlatform();
  final client = http.Client();
  const comparator = VersionComparator();
  final checker = UpdateChecker(httpClient: client, preferences: prefs,
    comparator: comparator, manifestUrl: manifest, githubOwner: 'pilialvu75-hue',
    githubRepo: repository, targetPlatform: UpdateTargetPlatform.android,
    windowsSetupAssetName: 'AIVEXUS-RendezVous-Setup-x64.exe',
    macosDmgAssetName: 'AIVEXUS-RendezVous-macOS.dmg', linuxDebAssetName: 'AIVEXUS-RendezVous-Linux-amd64.deb');
  final manager = UpdateManager(updateChecker: checker, comparator: comparator,
    preferences: prefs, intentHandler: AndroidIntentHandler(), currentVersion: info.version,
    allowDebugSignatureMismatchBypass: false, enableAndroidBetaBuildNumberComparison: true);
  runApp(MaterialApp(title: 'AIVEXUS RendezVous', theme: ThemeData(colorSchemeSeed: const Color(0xff125566)),
    home: RendezVous(manager: manager, client: client)));
}

String updateError(UpdateState s) {
  final message = (s.errorMessage ?? s.diagnostics.lastException ?? '').toLowerCase();
  if (message.contains('signature') || message.contains('verification') || message.contains('not valid') || message.contains('versioncode') || message.contains('split apk')) {
    return 'La mise à jour a été bloquée pour votre sécurité. Réessayez ou contactez l’assistance.';
  }
  if (s.diagnostics.canRequestPackageInstalls == false && s.diagnostics.apkDownloaded) {
    return 'Android nécessite votre autorisation pour installer cette mise à jour.';
  }
  if (message.contains('download')) return 'Téléchargement interrompu. Vérifiez votre connexion et réessayez.';
  if (message.contains('installer')) return 'Impossible de lancer l’installation. Réessayez.';
  return 'La mise à jour n’a pas pu être vérifiée ou installée. Vérifiez votre connexion et réessayez.';
}

class UpdateNoticePolicy {
  final Set<String> _seen = {};
  String? availableKey(UpdateState s) {
    if (!s.hasUpdate || s.usedCachedManifest || s.latestManifest == null) return null;
    return '${s.preferredChannel.name}:${s.latestManifest!.version}:${s.latestManifest!.versionCode ?? ""}';
  }
  bool shouldPrompt(UpdateState s) {
    final key=availableKey(s);
    return key!=null && !_seen.contains(key);
  }
  void markSeen(UpdateState s) {
    final key=availableKey(s);
    if(key!=null) _seen.add(key);
  }
}

class RendezVous extends StatefulWidget {
  const RendezVous({super.key, required this.manager, required this.client});
  final UpdateManager manager;
  final http.Client client;
  @override State<RendezVous> createState() => _RendezVousState();
}

class _RendezVousState extends State<RendezVous> with WidgetsBindingObserver {
  final notices=UpdateNoticePolicy();
  bool _pageOpen=false, _promptOpen=false, _scheduled=false, _foreground=true;
  String? _lastError;

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.manager.state.addListener(_stateChanged);
    unawaited(widget.manager.refreshDiagnostics());
    unawaited(widget.manager.startBackgroundChecks(interval: const Duration(minutes: 2)));
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground=state==AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(widget.manager.refreshDiagnostics());
      _stateChanged();
    }
  }
  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.manager.state.removeListener(_stateChanged);
    widget.manager.dispose(); widget.client.close(); super.dispose();
  }

  void _stateChanged() {
    if (_scheduled || !mounted) return;
    _scheduled=true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scheduled=false;
      if(!mounted || !_foreground || _pageOpen || _promptOpen || ModalRoute.of(context)?.isCurrent!=true) return;
      final s=widget.manager.state.value;
      if(s.status==UpdateStatus.error) {
        final error=updateError(s);
        if(_lastError!=error) {
          _lastError=error;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(error),action:SnackBarAction(label:'Détails',onPressed:(){unawaited(showUpdates());})));
        }
        return;
      }
      if(!notices.shouldPrompt(s)) return;
      notices.markSeen(s);
      _promptOpen=true;
      try {
        final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
          title:const Text('Nouvelle mise à jour'),
          content:Text('La version ${s.latestManifest!.version} est disponible. Voulez-vous consulter la mise à jour ?'),
          actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Plus tard')),
            FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Voir la mise à jour'))]));
        if(accepted==true&&mounted) await showUpdates();
      } finally { _promptOpen=false; }
      if(mounted) _stateChanged();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> showUpdates() async {
    if(_pageOpen||!mounted) return;
    _pageOpen=true;
    notices.markSeen(widget.manager.state.value);
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>UpdatePanel(manager:widget.manager)));
    } finally { _pageOpen=false; if(mounted) _stateChanged(); }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AIVEXUS RendezVous'), actions: [
      ValueListenableBuilder<UpdateState>(valueListenable: widget.manager.state,
        builder: (_, state, __) => IconButton(tooltip: 'Mises à jour', onPressed: showUpdates,
          icon: Icon(state.hasUpdate || state.status == UpdateStatus.readyToInstall ? Icons.system_update : state.status==UpdateStatus.error ? Icons.error_outline : Icons.update)))
    ]),
    body: const AndroidView(viewType: 'rendezvous/agenda'));
}

class UpdatePanel extends StatefulWidget {
  const UpdatePanel({super.key, required this.manager});
  final UpdateManager manager;
  @override State<UpdatePanel> createState()=>_UpdatePanelState();
}

class _UpdatePanelState extends State<UpdatePanel> with WidgetsBindingObserver {
  bool _actionBusy=false;
  String? _localError;
  UpdateManager get manager=>widget.manager;
  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(manager.refreshDiagnostics());
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed) unawaited(manager.refreshDiagnostics());
  }
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);super.dispose();}
  Future<void> run(Future<void> Function() action) async {
    if(_actionBusy)return;
    setState((){_actionBusy=true;_localError=null;});
    try{await action();}catch(_){if(mounted)setState(()=>_localError='Impossible de terminer cette opération. Réessayez.');}
    finally{if(mounted)setState(()=>_actionBusy=false);}
  }
  String label(UpdateStatus s)=>switch(s){
    UpdateStatus.idle=>'Prêt',
    UpdateStatus.checking=>'Recherche…',
    UpdateStatus.upToDate=>'Votre application est à jour',
    UpdateStatus.updateAvailable=>'Une mise à jour est disponible',
    UpdateStatus.downloading=>'Téléchargement…',
    UpdateStatus.readyToInstall=>'Mise à jour prête à installer',
    UpdateStatus.error=>'Mise à jour indisponible',
  };
  Future<void> download(UpdateState s) async {
    final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Télécharger la mise à jour ?'),
      content:Text('Version ${s.latestManifest!.version}. Vous pourrez confirmer l’installation ensuite.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Plus tard')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Télécharger'))]));
    if(accepted!=true||!mounted)return;
    if(manager.state.value.latestManifest?.version!=s.latestManifest?.version||!manager.state.value.hasUpdate||manager.state.value.usedCachedManifest)return;
    await manager.downloadLatestApk();
    await manager.refreshDiagnostics();
  }
  Future<void> install() async {
    await manager.refreshDiagnostics();
    if(!mounted)return;
    if(manager.state.value.diagnostics.canRequestPackageInstalls==false){
      final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Autorisation Android nécessaire'),
        content:const Text('Autorisez RendezVous à installer ses mises à jour, puis revenez ici pour confirmer l’installation.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Ouvrir les paramètres'))]));
      if(accepted==true&&mounted){
        final ok=await manager.openUnknownAppsSettings();
        if(!ok&&mounted)setState(()=>_localError='Impossible d’ouvrir les paramètres Android.');
      }
      return;
    }
    await manager.prepareInstallIntent();
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Mises à jour')),
    body:ValueListenableBuilder<UpdateState>(valueListenable:manager.state,builder:(ctx,s,_){
      final busy=_actionBusy||s.status==UpdateStatus.checking||s.status==UpdateStatus.downloading;
      final ready=s.status==UpdateStatus.readyToInstall;
      return ListView(padding:const EdgeInsets.all(20),children:[
        Text('Version installée : ${s.currentVersion}',style:Theme.of(context).textTheme.titleMedium),
        if(s.latestManifest!=null) Text('Dernière version détectée : ${s.latestManifest!.version}'),
        const SizedBox(height:20),
        Text(label(s.status),style:Theme.of(context).textTheme.titleLarge),
        if(s.usedCachedManifest) const Text('Résultat précédent : connexion à vérifier avant le téléchargement.'),
        if(s.status==UpdateStatus.error) Text(updateError(s),style:TextStyle(color:Theme.of(context).colorScheme.error)),
        if(_localError!=null) Text(_localError!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
        if(s.status==UpdateStatus.downloading)...[
          const SizedBox(height:12),
          LinearProgressIndicator(value:s.downloadProgress.clamp(0.0,1.0).toDouble()),
          Text('${(s.downloadProgress.clamp(0.0,1.0)*100).round()} %'),
        ],
        const SizedBox(height:24),
        if(s.hasUpdate&&!s.usedCachedManifest) FilledButton(onPressed:busy?null:()=>run(()=>download(s)),child:const Text('Télécharger')),
        if(ready) FilledButton(onPressed:busy?null:()=>run(install),child:const Text('Installer')),
        OutlinedButton(onPressed:busy||ready?null:()=>run(()async{await manager.checkForUpdates(allowCachedFallback:false);await manager.refreshDiagnostics();}),child:const Text('Rechercher une mise à jour')),
        const SizedBox(height:24),
        const Text('Canal de mise à jour'),
        DropdownButton<ReleaseChannel>(value:s.preferredChannel,isExpanded:true,
          items:[for(final c in ReleaseChannel.values) DropdownMenuItem(value:c,child:Text(c.name))],
          onChanged:busy||ready?null:(c){if(c!=null)unawaited(run(()=>manager.setPreferredChannel(c)));}),
      ]);
    }));
}
