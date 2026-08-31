import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';

/// Pins the reassembly of a streamed tool call.
///
/// The failure this guards against is silent by construction: a call that is
/// dropped, doubled or truncated reaches the agent loop as "the model chose to
/// answer directly" or as a tool complaining about its own arguments, never as
/// a protocol error. Both dialects the accumulator serves are covered — ①'s
/// deltas and DashScope's cumulative frames — because one class parses both
/// and any given channel exercises only one of them.
void main() {
  group('StreamingToolCallAccumulator — incremental deltas', () {
    test('assembles one call from fragmented arguments', () {
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'index': 0,
            'id': 'call_abc',
            'type': 'function',
            'function': {'name': 'get_weather', 'arguments': ''},
          }
        ])
        ..feed([
          {
            'index': 0,
            'function': {'arguments': '{"loc'},
          }
        ])
        ..feed([
          {
            'index': 0,
            'function': {'arguments': 'ation":"Hangzhou"}'},
          }
        ]);

      final calls = acc.flush();
      expect(calls, hasLength(1));
      expect(calls.single.id, 'call_abc');
      expect(calls.single.name, 'get_weather');
      expect(calls.single.arguments, {'location': 'Hangzhou'});
    });

    test('keeps interleaved parallel calls apart by index', () {
      // The whole reason `index` is the grouping key: both calls are open at
      // once and their fragments arrive mixed.
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'index': 0,
            'id': 'call_a',
            'function': {'name': 'read_file', 'arguments': '{"p'},
          },
          {
            'index': 1,
            'id': 'call_b',
            'function': {'name': 'list_dir', 'arguments': '{"d'},
          },
        ])
        ..feed([
          {
            'index': 1,
            'function': {'arguments': 'ir":"/tmp"}'},
          }
        ])
        ..feed([
          {
            'index': 0,
            'function': {'arguments': 'ath":"a.txt"}'},
          }
        ]);

      final calls = acc.flush();
      expect(calls.map((c) => c.name).toList(), ['read_file', 'list_dir']);
      expect(calls[0].arguments, {'path': 'a.txt'});
      expect(calls[1].arguments, {'dir': '/tmp'});
    });

    test('appends a nested object opening instead of restarting on it', () {
      // `{` arriving mid-arguments is a delta, not a cumulative frame — the
      // merge must not read it as "the document starts over".
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'index': 0,
            'id': 'c',
            'function': {'name': 'search', 'arguments': '{"filter":'},
          }
        ])
        ..feed([
          {
            'index': 0,
            'function': {'arguments': '{'},
          }
        ])
        ..feed([
          {
            'index': 0,
            'function': {'arguments': '"x":1}}'},
          }
        ]);

      expect(acc.flush().single.arguments, {
        'filter': {'x': 1}
      });
    });

    test('appends a delta that opens by repeating the whole accumulation', () {
      // `{"a":{"a":1}}` split at a token boundary: the second fragment starts
      // with everything received so far. The prefix heuristic alone read that
      // as a cumulative repeat and replaced the accumulation — the arguments
      // decoded as {} and the tool ran on nothing. A nameless frame on a
      // named call is a delta by construction, so it must append.
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'index': 0,
            'id': 'c',
            'function': {'name': 'search', 'arguments': '{"a":'},
          }
        ])
        ..feed([
          {
            'index': 0,
            'function': {'arguments': '{"a":1}}'},
          }
        ]);

      expect(acc.flush().single.arguments, {
        'a': {'a': 1}
      });
    });

    test('falls back to array position when a relay omits index', () {
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'id': 'call_a',
            'function': {'name': 'one', 'arguments': '{}'},
          },
          {
            'id': 'call_b',
            'function': {'name': 'two', 'arguments': '{}'},
          },
        ]);

      expect(acc.flush().map((c) => c.name).toList(), ['one', 'two']);
    });

    test('keeps index-less calls apart when they arrive in separate frames',
        () {
      // The other way a relay omits index: each call complete, one per chunk,
      // every one at array position 0. Merging them by position blends two
      // calls into one — the id is what tells them apart.
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'id': 'call_a',
            'function': {'name': 'get_weather', 'arguments': '{"city":"HZ"}'},
          },
        ])
        ..feed([
          {
            'id': 'call_b',
            'function': {'name': 'get_time', 'arguments': '{"tz":"UTC"}'},
          },
        ]);

      final calls = acc.flush();
      expect(calls.map((c) => c.name).toList(), ['get_weather', 'get_time']);
      expect(calls[0].arguments, {'city': 'HZ'});
      expect(calls[1].arguments, {'tz': 'UTC'});
    });

    test('an index-less cumulative repeat still joins its own call by id', () {
      // Cumulative dialect with the index dropped by an intermediary: the
      // repeated id must route the frame back to the same slot, not open a
      // second call.
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'id': 'call_1',
            'function': {'name': 'view_image', 'arguments': '{"path"'},
          },
        ])
        ..feed([
          {
            'id': 'call_1',
            'function': {'name': 'view_image', 'arguments': '{"path":"a.png"}'},
          },
        ]);

      final call = acc.flush().single;
      expect(call.name, 'view_image');
      expect(call.arguments, {'path': 'a.png'});
    });

    test('keeps index-less calls apart when only openers carry id', () {
      // The fragmented variant: id + name arrive only on each call's opening
      // frame, then bare `arguments` deltas with neither index nor id. Array
      // position 0 would merge call B's argument tail onto call A; a bare
      // fragment must follow the call that is actually streaming.
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'id': 'call_a',
            'function': {'name': 'get_weather', 'arguments': '{"city":'},
          },
        ])
        ..feed([
          {
            'function': {'arguments': '"HZ"}'},
          },
        ])
        ..feed([
          {
            'id': 'call_b',
            'function': {'name': 'get_time', 'arguments': '{"tz":'},
          },
        ])
        ..feed([
          {
            'function': {'arguments': '"UTC"}'},
          },
        ]);

      final calls = acc.flush();
      expect(calls.map((c) => c.name).toList(), ['get_weather', 'get_time']);
      expect(calls[0].arguments, {'city': 'HZ'});
      expect(calls[1].arguments, {'tz': 'UTC'});
    });

    test('synthesizes an id when the relay assigns none', () {
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'index': 2,
            'id': '',
            'function': {'name': 'noop', 'arguments': '{}'},
          }
        ]);

      // Empty is treated as absent — two id-less calls in one batch must not
      // collide, or the next request is rejected for a duplicate id.
      expect(acc.flush().single.id, 'call_2');
    });
  });

  group('StreamingToolCallAccumulator — cumulative frames', () {
    test('does not double a call repeated whole on every frame', () {
      // DashScope refusing `incremental_output`, or an intermediary
      // re-assembling the stream: each frame restates everything so far.
      // Appending them would build `view_imageview_image` and arguments that
      // parse as nothing.
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'index': 0,
            'id': 'call_1',
            'function': {'name': 'view_image', 'arguments': '{"path"'},
          }
        ])
        ..feed([
          {
            'index': 0,
            'id': 'call_1',
            'function': {'name': 'view_image', 'arguments': '{"path":"a.png"}'},
          }
        ])
        ..feed([
          {
            'index': 0,
            'id': 'call_1',
            'function': {'name': 'view_image', 'arguments': '{"path":"a.png"}'},
          }
        ]);

      final call = acc.flush().single;
      expect(call.id, 'call_1');
      expect(call.name, 'view_image');
      expect(call.arguments, {'path': 'a.png'});
    });

    test('does not double a cumulative call that restates id but drops name',
        () {
      // A cumulative dialect that repeats the full arguments each frame and
      // keeps the id, but sends `name` only on the opener. The second frame is
      // a full restatement, not a delta — appending it would double the
      // arguments. The retained id is what tells it apart from a bare ①
      // continuation and routes it back through the prefix merge.
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'index': 0,
            'id': 'call_1',
            'function': {'name': 'view_image', 'arguments': '{"path":'},
          }
        ])
        ..feed([
          {
            'index': 0,
            'id': 'call_1',
            'function': {'arguments': '{"path":"a.png"}'},
          }
        ]);

      final call = acc.flush().single;
      expect(call.name, 'view_image');
      expect(call.arguments, {'path': 'a.png'});
    });
  });

  group('StreamingToolCallAccumulator — degenerate payloads', () {
    test('a tool taking no arguments yields an empty map, not a failure', () {
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'index': 0,
            'id': 'c',
            'function': {'name': 'ping', 'arguments': ''},
          }
        ]);

      expect(acc.flush().single.arguments, isEmpty);
    });

    test('a stream cut mid-arguments still emits the call', () {
      // Dropping it would read to an agent loop as "the model answered
      // directly" — the one failure mode it cannot detect. The tool reports
      // the missing argument itself.
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'index': 0,
            'id': 'c',
            'function': {'name': 'write_file', 'arguments': '{"path":"a.txt"'},
          }
        ]);

      final call = acc.flush().single;
      expect(call.name, 'write_file');
      expect(call.arguments, isEmpty);
    });

    test('accepts arguments a relay sent as an object', () {
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'index': 0,
            'id': 'c',
            'function': {
              'name': 'search',
              'arguments': {'q': 'hi'},
            },
          }
        ]);

      expect(acc.flush().single.arguments, {'q': 'hi'});
    });

    test('ignores chunks carrying no tool_calls at all', () {
      final acc = StreamingToolCallAccumulator()
        ..feed(null)
        ..feed('not a list')
        ..feed(<dynamic>[]);

      expect(acc.isEmpty, isTrue);
      expect(acc.flush(), isEmpty);
    });

    test('flush empties the accumulator so a turn cannot replay', () {
      final acc = StreamingToolCallAccumulator()
        ..feed([
          {
            'index': 0,
            'id': 'c',
            'function': {'name': 'ping', 'arguments': '{}'},
          }
        ]);

      expect(acc.flush(), hasLength(1));
      expect(acc.isEmpty, isTrue);
      expect(acc.flush(), isEmpty);
    });
  });

  group('decodeToolArguments', () {
    test('recovers concatenated JSON objects', () {
      // A relay prefixing real arguments with a stray empty-object
      // placeholder; plain jsonDecode rejects the trailing data.
      expect(decodeToolArguments('{}{"id": 1}'), {'id': 1});
    });

    test('returns empty for blank, unparseable and non-map payloads', () {
      expect(decodeToolArguments(''), isEmpty);
      expect(decodeToolArguments('   '), isEmpty);
      expect(decodeToolArguments('{"a":'), isEmpty);
      expect(decodeToolArguments('[1,2]'), isEmpty);
      expect(decodeToolArguments(null), isEmpty);
    });

    test('passes an already-decoded object through', () {
      expect(decodeToolArguments({'a': 1}), {'a': 1});
    });
  });
}
