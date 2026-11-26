import 'package:flutter_test/flutter_test.dart';
import 'package:aivexus_original_updater/aivexus_original_updater.dart';
import '../lib/main.dart';

UpdateState state({String version='0.2.6', int code=8, bool cached=false, UpdateStatus status=UpdateStatus.updateAvailable, ReleaseChannel channel=ReleaseChannel.beta}) =>
  UpdateState(status:status,currentVersion:'0.2.5',preferredChannel:channel,usedCachedManifest:cached,
    latestManifest:UpdateManifest(version:version,versionCode:code,channel:channel,minSupported:'0.2.2',apkUrl:'https://example.test/rv.apk',changelog:'',critical:false));
void main(){
  test('Only fresh available updates prompt; once per version and channel',(){
    final p=UpdateNoticePolicy();
    expect(p.shouldPrompt(state(cached:true)),false);
    expect(p.shouldPrompt(state(status:UpdateStatus.upToDate)),false);
    expect(p.shouldPrompt(state(status:UpdateStatus.downloading)),false);
    expect(p.shouldPrompt(state()),true);
    p.markSeen(state());
    expect(p.shouldPrompt(state()),false);
    expect(p.shouldPrompt(state(version:'0.2.7',code:9)),true);
    expect(p.shouldPrompt(state(code:9)),true);
    expect(p.shouldPrompt(state(channel:ReleaseChannel.stable)),true);
  });
  test('User errors are localized and do not expose exception details',(){
    final s=state(status:UpdateStatus.error).copyWith(errorMessage:'APK signature does not match /private/path');
    expect(updateError(s),contains('sécurité'));
    expect(updateError(s),isNot(contains('/private/path')));
  });
}
