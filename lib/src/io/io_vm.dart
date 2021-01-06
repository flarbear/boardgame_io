import 'dart:convert';
import 'dart:io';

class io {
  static Future<T> _withClient<T>(Future<T> fn(HttpClient)) async {
    final HttpClient client = HttpClient();
    try {
      return await fn(client);
    } finally {
      client.close();
    }
  }

  static Future<dynamic> getBody(Uri uri) => _withClient((httpClient) async {
    HttpClientRequest request = await httpClient.getUrl(uri);
    HttpClientResponse response = await request.close();
    String reply = await response.transform(utf8.decoder).join();
    return JsonDecoder().convert(reply);
  });

  static Future<dynamic> postBody(Uri uri, Map<String, String> parameters) => _withClient((httpClient) async {
    HttpClientRequest request = await httpClient.postUrl(uri);
    request.headers.contentType = ContentType.json;
    String bodyString = JsonEncoder().convert(parameters);
    request.write(bodyString);
    HttpClientResponse response = await request.close();
    String reply = await response.transform(utf8.decoder).join();
    return JsonDecoder().convert(reply);
  });
}
