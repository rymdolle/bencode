%%% Copyright (c) 2019 Olle Mattsson <rymdolle@gmail.com>
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.

-module(bencode).

%% API
-export([encode/1]).
-export([decode/1, decode/2]).

-type bencode() ::
        integer() | binary() | [{binary(), bencode()}] | [bencode()].

%% @doc Generate binary from internal format
%% @end
-spec encode(bencode()) -> binary().
encode(Bin) when is_binary(Bin) ->
    <<(integer_to_binary(byte_size(Bin)))/binary, $:, Bin/binary>>;
encode(Int) when is_integer(Int) ->
    <<$i, (integer_to_binary(Int))/binary, $e>>;
encode([{}]) ->
    %% Empty dictionary
    <<"de">>;
encode(Dict = [{_, _}|_]) ->
    %% Discard keys that are not binaries
    <<$d,<< <<(encode(K))/binary,(encode(V))/binary>> ||
             {K,V} <- lists:keysort(1, Dict), is_binary(K) >>/binary,$e>>;
encode(List) when is_list(List) ->
    <<$l,<< <<(encode(Item))/binary>> || Item <- List >>/binary,$e>>.

%% @doc Parse bencoded binary
%% @end
-spec decode(binary()) -> {ok, bencode()}.
decode(Data) ->
    decode(Data, true).

-spec decode(binary(), Strict :: boolean()) -> {ok, bencode(), binary()} |
                                               {ok, bencode()}.
decode(Data, true) ->
    {ok, Item, <<>>} = decode_item(Data),
    {ok, Item};
decode(Data, false) ->
    decode_item(Data).


%%% Internal functions

%% @private
decode_item(<<$d, Rest/binary>>) ->
    decode_dictionary(Rest, []);
decode_item(<<$i, Rest/binary>>) ->
    [Int, Rest2] = binary:split(Rest, <<"e">>),
    {ok, binary_to_integer(Int), Rest2};
decode_item(<<$l,Rest/binary>>) ->
    decode_list(Rest, []);
decode_item(Data = <<H,_/binary>>) when H >= $0 andalso H =< $9 ->
    decode_string(Data).

%% @private
decode_dictionary(<<$e, Rest/binary>>, []) ->
    %% Empty dictionary same as list
    {ok, [], Rest};
decode_dictionary(<<$e, Rest/binary>>, Acc) ->
    {ok, lists:reverse(Acc), Rest};
decode_dictionary(Data, Acc) ->
    {ok, String, Rest} = decode_string(Data),
    {ok, Ret, Rest2} = decode_item(Rest),
    decode_dictionary(Rest2, [{String, Ret}|Acc]).

%% @private
decode_list(<<$e, Rest/binary>>, Acc) ->
    {ok, lists:reverse(Acc), Rest};
decode_list(Data, Acc) ->
    {ok, Ret, Rest} = decode_item(Data),
    decode_list(Rest, [Ret|Acc]).

%% @private
decode_string(<<"0:", Rest/binary>>) ->
    {ok, <<>>, Rest};
decode_string(Data) ->
    [Int, Rest] = binary:split(Data, <<":">>),
    Length = binary_to_integer(Int),
    <<String:Length/binary, Rest2/binary>> = Rest,
    {ok, String, Rest2}.


%%% Tests

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

integer_test_() ->
    [
     ?_assertEqual({ok, 123}, decode(<<"i123e">>)),
     ?_assertEqual({ok, 0},   decode(<<"i0e">>)),
     ?_assertEqual({ok, -10}, decode(<<"i-10e">>)),

     ?_assertEqual({ok, 0, <<1,2,3>>},   decode(<<"i0e",1,2,3>>, false)),
     ?_assertException(error, _, decode(<<"i0e",1,2,3>>, true)),

     ?_assertEqual(<<"i123e">>, encode(123)),
     ?_assertEqual(<<"i0e">>,   encode(0)),
     ?_assertEqual(<<"i-10e">>, encode(-10))
    ].

string_test_() ->
    [
     ?_assertEqual({ok, <<"word">>}, decode(<<"4:word">>)),
     ?_assertEqual({ok, <<"word">>, <<1,2,3>>}, decode(<<"4:word",1,2,3>>, false)),

     ?_assertException(error, _, decode(<<"4:word",1,2,3>>, true)),

     ?_assertEqual(<<"4:word">>, encode(<<"word">>))
    ].

dict_test() ->
    [
     ?_assertEqual({ok, []}, decode(<<"de">>)),
     ?_assertEqual({ok, [], <<1,2,3>>}, decode(<<"de",1,2,3>>, false)),
     ?_assertEqual([{<<"a">>,0},{<<"b">>,0},{<<"c">>,0}],
                   decode(<<"d1:ai0e1:bi0e1:ci0ee">>, false)),
     ?_assertException(error, _, decode(<<"dlei0ee">>)),

     ?_assertException(error, _, decode(<<"de",1,2,3>>, true)),

     ?_assertEqual(<<"de">>, encode([{}])),
     ?_assertEqual(<<"de">>, encode([{1, 0}, {[], <<"a">>}])),
     ?_assertEqual(<<"d1:ai0e1:bi0e1:ci0ee">>,
                   encode([{<<"c">>,0},{<<"b">>,0},{<<"a">>,0}]))
    ].

list_test_() ->
    [
     ?_assertEqual({ok, [], <<>>}, decode(<<"le">>, false)),
     ?_assertEqual({ok, []}, decode(<<"le">>, true)),
     ?_assertEqual({ok, [], <<1,2,3>>}, decode(<<"le",1,2,3>>, false)),
     ?_assertEqual({ok, [1,2,3], <<>>}, decode(<<"li1ei2ei3ee">>, false)),

     ?_assertException(error, _, decode(<<"le",1,2,3>>, true)),

     ?_assertEqual(<<"le">>, encode([])),
     ?_assertEqual(<<"li3ei2ei1ee">>, encode([3,2,1]))
    ].

mixed_test_() ->
    Tests = [
             {[420,<<"string">>,[],[{<<"a">>,[]}]],
              <<"li420e6:stringled1:aleee">>},

             {[<<"hello world">>], <<"l11:hello worlde">>},

             {[{<<"another">>, 200},
               {<<"key">>, <<"value">>},
               {<<"third">>, [{<<"sub">>, 132}]}],
              <<"d7:anotheri200e3:key5:value5:thirdd3:subi132eee">>}
            ],
    lists:append([[?_assertEqual({ok, Decoded}, decode(Encoded)),
                   ?_assertEqual({ok, Decoded, <<>>}, decode(Encoded, false)),
                   ?_assertEqual(Encoded, encode(Decoded))] ||
                     {Decoded, Encoded} <- Tests]).

-endif.
