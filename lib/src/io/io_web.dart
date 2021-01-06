import 'dart:convert';
import 'dart:html';

class io {
  static Future<dynamic> getBody(Uri uri) async {
    String reply = await HttpRequest.getString(uri.toString());
    return JsonDecoder().convert(reply);
  }

  static Future<dynamic> postBody(Uri uri, Map<String, String> parameters) async {
    HttpRequest request = await HttpRequest.postFormData(uri.toString(), parameters);
    return JsonDecoder().convert(request.responseText!);
  }
}
