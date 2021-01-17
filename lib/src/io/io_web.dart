/*
 * Copyright 2021 flarbear@github
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT.
 */

import 'dart:convert';
import 'dart:html';

class io {
  static Future<dynamic> getBody(Uri uri) async {
    String reply = await HttpRequest.getString(uri.toString());
    return JsonDecoder().convert(reply);
  }

  static Future<dynamic> postBody(Uri uri, Map<String, dynamic> parameters) async {
    HttpRequest request = await HttpRequest.request(
      uri.toString(),
      method: 'POST',
      requestHeaders: { 'Content-Type': 'application/json' },
      sendData: JsonEncoder().convert(parameters),
    );
    return JsonDecoder().convert(request.responseText!);
  }
}
