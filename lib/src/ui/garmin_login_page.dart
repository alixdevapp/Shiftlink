// Connexion à Garmin Connect : la page de connexion de Garmin s'ouvre dans ShiftLink.
// Tu y tapes ton e-mail, ton mot de passe et le code de validation si Garmin en demande un.
// ShiftLink ne lit pas ce que tu tapes : il attend seulement le ticket que Garmin renvoie
// une fois connecté, puis ferme la page.
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../i18n.dart';
import '../net/garmin_connect.dart';

/// Renvoie le ticket Garmin (ST-…) et la connexion utilisée, ou null si on a fermé la page.
class GarminLoginPage extends StatefulWidget {
  final GarminLoginFlow flow;
  const GarminLoginPage({super.key, this.flow = GarminLoginFlow.mobile});

  @override
  State<GarminLoginPage> createState() => _GarminLoginPageState();
}

class _GarminLoginPageState extends State<GarminLoginPage> {
  late final WebViewController _web;
  late GarminLoginFlow _flow = widget.flow;
  bool _loading = true;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('ShiftLinkGarmin', onMessageReceived: (m) => _catch(m.message))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            if (_catch(req.url)) return NavigationDecision.prevent;
            return NavigationDecision.navigate;
          },
          onUrlChange: (c) => _catch(c.url ?? ''),
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) async {
            if (mounted) setState(() => _loading = false);
            // La page « appli mobile » de Garmin donne le ticket à l'appli Garmin au lieu de
            // changer de page : on écoute les réponses de son formulaire de connexion.
            try {
              await _web.runJavaScript(_listenScript);
            } catch (_) {}
            // Certaines pages de Garmin écrivent le ticket dans la page au lieu d'y aller.
            try {
              final html = await _web.runJavaScriptReturningResult('document.documentElement.outerHTML');
              _catch('$html');
            } catch (_) {}
          },
        ),
      );
    _setUp();
  }

  /// La vérification anti-robots de Garmin (Cloudflare) tourne en boucle dans une page intégrée
  /// si elle se voit en « WebView » ou si elle ne peut pas poser ses cookies : on se présente
  /// comme Chrome et on accepte ses cookies.
  Future<void> _setUp() async {
    try {
      final ua = await _web.getUserAgent();
      if (ua != null) {
        await _web.setUserAgent(ua.replaceAll('; wv', '').replaceAll(RegExp(r'Version/[\d.]+ '), ''));
      }
    } catch (_) {}
    try {
      final p = _web.platform;
      if (p is AndroidWebViewController) {
        await AndroidWebViewCookieManager(
          const PlatformWebViewCookieManagerCreationParams(),
        ).setAcceptThirdPartyCookies(p, true);
      }
    } catch (_) {}
    await _web.loadRequest(_flow.signInUri);
  }

  static const _listenScript = '''
(function () {
  if (window.__shiftlinkGarmin) return;
  window.__shiftlinkGarmin = true;
  function look(t) {
    try { if (t && String(t).indexOf('ST-') >= 0) ShiftLinkGarmin.postMessage(String(t)); } catch (e) {}
  }
  var send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function () {
    this.addEventListener('load', function () { try { look(this.responseText); } catch (e) {} });
    return send.apply(this, arguments);
  };
  if (window.fetch) {
    var f = window.fetch;
    window.fetch = function () {
      return f.apply(this, arguments).then(function (r) {
        try { r.clone().text().then(look); } catch (e) {}
        return r;
      });
    };
  }
})();
''';

  bool _catch(String text) {
    if (_done) return true;
    final t = GarminConnectClient.ticketIn(text);
    if (t == null) return false;
    _done = true;
    if (mounted) Navigator.of(context).pop((t, _flow));
    return true;
  }

  Future<void> _restart({bool otherWay = false}) async {
    await WebViewCookieManager().clearCookies();
    await _web.clearCache();
    if (otherWay) {
      _flow = _flow == GarminLoginFlow.portal ? GarminLoginFlow.mobile : GarminLoginFlow.portal;
    }
    await _web.loadRequest(_flow.signInUri);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('Connexion à Garmin Connect')),
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) => _restart(otherWay: v == 'other'),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'restart', child: Text(tr('Recommencer'))),
            PopupMenuItem(value: 'other', child: Text(tr('Essayer l’autre page de connexion'))),
          ],
        ),
      ],
      bottom: _loading
          ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3))
          : null,
    ),
    body: WebViewWidget(controller: _web),
  );
}
