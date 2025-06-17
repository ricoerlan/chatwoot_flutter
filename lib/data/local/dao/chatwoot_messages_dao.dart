import 'dart:collection';

import 'package:chatwoot_flutter/data/local/entity/chatwoot_message.dart';
import 'package:hive_flutter/hive_flutter.dart';

abstract class ChatwootMessagesDao {
  Future<void> saveMessage(ChatwootMessage message);
  Future<void> saveAllMessages(List<ChatwootMessage> messages);
  ChatwootMessage? getMessage(int messageId);
  List<ChatwootMessage> getMessages();
  Future<void> clear();
  Future<void> deleteMessage(int messageId);
  Future<void> onDispose();
  Future<void> markMessageAsRead(int messageId);
  bool isMessageRead(int messageId);
  Set<int> getReadMessageIds();

  Future<void> clearAll();
}

//Only used when persistence is enabled
enum ChatwootMessagesBoxNames { MESSAGES, MESSAGES_TO_CLIENT_INSTANCE_KEY, READ_MESSAGES }

class PersistedChatwootMessagesDao extends ChatwootMessagesDao {
  // box containing all persisted messages
  final Box<ChatwootMessage> _box;

  final String _clientInstanceKey;

  //box with one to many relation
  final Box<String> _messageIdToClientInstanceKeyBox;
  
  // box containing read message IDs for each client instance
  final Box<List<dynamic>> _readMessagesBox;

  PersistedChatwootMessagesDao(
      this._box,
      this._messageIdToClientInstanceKeyBox,
      this._readMessagesBox,
      this._clientInstanceKey);

  @override
  Future<void> clear() async {
    //filter current client instance message ids
    Iterable clientMessageIds = _messageIdToClientInstanceKeyBox.keys.where(
        (key) =>
            _messageIdToClientInstanceKeyBox.get(key) == _clientInstanceKey);

    await _box.deleteAll(clientMessageIds);
    await _messageIdToClientInstanceKeyBox.deleteAll(clientMessageIds);
    await _readMessagesBox.delete(_clientInstanceKey); // Clear read messages for this client instance
  }

  @override
  Future<void> saveMessage(ChatwootMessage message) async {
    await _box.put(message.id, message);
    await _messageIdToClientInstanceKeyBox.put(message.id, _clientInstanceKey);
    print("saved");
  }

  @override
  Future<void> saveAllMessages(List<ChatwootMessage> messages) async {
    for (ChatwootMessage message in messages) await saveMessage(message);
  }

  @override
  List<ChatwootMessage> getMessages() {
    final messageClientInstancekey = _clientInstanceKey;

    //filter current client instance message ids
    Set<int> clientMessageIds = _messageIdToClientInstanceKeyBox.keys
        .map((e) => e as int)
        .where((key) =>
            _messageIdToClientInstanceKeyBox.get(key) ==
            messageClientInstancekey)
        .toSet();

    //retrieve messages with ids
    List<ChatwootMessage> sortedMessages = _box.values
        .where((message) => clientMessageIds.contains(message.id))
        .toList(growable: false);

    //sort message using creation dates
    sortedMessages.sort((a, b) {
      return b.createdAt.compareTo(a.createdAt);
    });

    return sortedMessages;
  }

  @override
  Future<void> onDispose() async {}
  
  @override
  Future<void> markMessageAsRead(int messageId) async {
    // Get current read message IDs or initialize empty list
    List<dynamic> readIds = _readMessagesBox.get(_clientInstanceKey, defaultValue: []) ?? [];
    
    // Add messageId if not already present
    if (!readIds.contains(messageId)) {
      readIds.add(messageId);
      await _readMessagesBox.put(_clientInstanceKey, readIds);
    }
  }
  
  @override
  bool isMessageRead(int messageId) {
    // Get read message IDs for current client instance
    final readIds = _readMessagesBox.get(_clientInstanceKey, defaultValue: []) ?? [];
    return readIds.contains(messageId);
  }
  
  @override
  Set<int> getReadMessageIds() {
    // Get read message IDs for current client instance as Set<int>
    final readIds = _readMessagesBox.get(_clientInstanceKey, defaultValue: []) ?? [];
    return readIds.map((id) => id as int).toSet();
  }

  @override
  Future<void> deleteMessage(int messageId) async {
    await _box.delete(messageId);
    await _messageIdToClientInstanceKeyBox.delete(messageId);
  }

  @override
  ChatwootMessage? getMessage(int messageId) {
    return _box.get(messageId, defaultValue: null);
  }

  @override
  Future<void> clearAll() async {
    await _box.clear();
    await _messageIdToClientInstanceKeyBox.clear();
    await _readMessagesBox.clear();
  }

  static Future<void> openDB() async {
    await Hive.openBox<ChatwootMessage>(
        ChatwootMessagesBoxNames.MESSAGES.toString());
    await Hive.openBox<String>(
        ChatwootMessagesBoxNames.MESSAGES_TO_CLIENT_INSTANCE_KEY.toString());
    await Hive.openBox<List<dynamic>>(
        ChatwootMessagesBoxNames.READ_MESSAGES.toString());
  }
}

class NonPersistedChatwootMessagesDao extends ChatwootMessagesDao {
  HashMap<int, ChatwootMessage> _messages = new HashMap();
  Set<int> _readMessageIds = {};

  @override
  Future<void> clear() async {
    _messages.clear();
    _readMessageIds.clear();
  }

  @override
  Future<void> deleteMessage(int messageId) async {
    _messages.remove(messageId);
  }

  @override
  ChatwootMessage? getMessage(int messageId) {
    return _messages[messageId];
  }

  @override
  List<ChatwootMessage> getMessages() {
    List<ChatwootMessage> sortedMessages =
        _messages.values.toList(growable: false);
    sortedMessages.sort((a, b) {
      return a.createdAt.compareTo(b.createdAt);
    });
    return sortedMessages;
  }

  @override
  Future<void> onDispose() async {
    _messages.clear();
  }

  @override
  Future<void> saveAllMessages(List<ChatwootMessage> messages) async {
    messages.forEach((element) async {
      await saveMessage(element);
    });
  }

  @override
  Future<void> saveMessage(ChatwootMessage message) async {
    _messages.update(message.id, (value) => message, ifAbsent: () => message);
  }
  
  @override
  Future<void> markMessageAsRead(int messageId) async {
    _readMessageIds.add(messageId);
  }
  
  @override
  bool isMessageRead(int messageId) {
    return _readMessageIds.contains(messageId);
  }
  
  @override
  Set<int> getReadMessageIds() {
    return _readMessageIds;
  }

  @override
  Future<void> clearAll() async {
    _messages.clear();
    _readMessageIds.clear();
  }
}
