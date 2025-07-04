import 'package:chatwoot_flutter/chatwoot_flutter.dart';
import 'package:chatwoot_flutter/data/chatwoot_repository.dart';
import 'package:chatwoot_flutter/data/local/entity/chatwoot_contact.dart';
import 'package:chatwoot_flutter/data/local/entity/chatwoot_conversation.dart';
import 'package:chatwoot_flutter/data/remote/requests/chatwoot_action_data.dart';
import 'package:chatwoot_flutter/data/remote/requests/chatwoot_new_message_request.dart';
import 'package:chatwoot_flutter/di/modules.dart';
import 'package:chatwoot_flutter/chatwoot_parameters.dart';
import 'package:chatwoot_flutter/repository_parameters.dart';
import 'package:riverpod/riverpod.dart';

import 'data/local/local_storage.dart';

/// Represents a chatwoot client instance. All chatwoot operations (Example: sendMessages) are
/// passed through chatwoot client. For more info visit
/// https://www.chatwoot.com/docs/product/channels/api/client-apis
///
/// {@category FlutterClientSdk}
class ChatwootClient {
  late final ChatwootRepository _repository;
  final ChatwootParameters _parameters;
  final ChatwootCallbacks? callbacks;
  final ChatwootUser? user;

  String get baseUrl => _parameters.baseUrl;

  String get inboxIdentifier => _parameters.inboxIdentifier;

  ChatwootClient._(this._parameters, {this.user, this.callbacks}) {
    providerContainerMap.putIfAbsent(
      _parameters.clientInstanceKey,
      () => ProviderContainer(),
    );
    final container = providerContainerMap[_parameters.clientInstanceKey]!;
    _repository = container.read(
      chatwootRepositoryProvider(
        RepositoryParameters(
          params: _parameters,
          callbacks: callbacks ?? ChatwootCallbacks(),
        ),
      ),
    );
  }

  void _init() {
    try {
      _repository.initialize(user);
    } on ChatwootClientException catch (e) {
      callbacks?.onError?.call(e);
    }
  }

  ///Retrieves chatwoot client's messages. If persistence is enabled [ChatwootCallbacks.onPersistedMessagesRetrieved]
  ///will be triggered with persisted messages. On successfully fetch from remote server
  ///[ChatwootCallbacks.onMessagesRetrieved] will be triggered
  void loadMessages() async {
    _repository.getPersistedMessages();
    await _repository.getMessages();
  }

  /// Sends chatwoot message. The echoId is your temporary message id. When message sends successfully
  /// [ChatwootMessage] will be returned with the [echoId] on [ChatwootCallbacks.onMessageSent]. If
  /// message fails to send [ChatwootCallbacks.onError] will be triggered [echoId] as data.
  Future<void> sendMessage({
    required String content,
    required String echoId,
  }) async {
    final request = ChatwootNewMessageRequest(content: content, echoId: echoId);
    await _repository.sendMessage(request);
  }

  ///Send chatwoot action performed by user.
  ///
  /// Example: User started typing
  Future<void> sendAction(ChatwootActionType action) async {
    _repository.sendAction(action);
  }

  ///Disposes chatwoot client and cancels all stream subscriptions
  dispose() {
    final container = providerContainerMap[_parameters.clientInstanceKey]!;
    _repository.dispose();
    container.dispose();
    providerContainerMap.remove(_parameters.clientInstanceKey);
  }

  /// Clears all chatwoot client data
  clearClientData() {
    final container = providerContainerMap[_parameters.clientInstanceKey]!;
    final localStorage = container.read(localStorageProvider(_parameters));
    localStorage.clear(clearChatwootUserStorage: false);
  }

  /// Retrieves the ChatwootContact from local storage
  /// Returns null if no contact is found
  Future<ChatwootContact?> getContact() async {
    final container = providerContainerMap[_parameters.clientInstanceKey]!;
    final localStorage = container.read(localStorageProvider(_parameters));
    return await localStorage.contactDao.getContact();
  }

  /// Gets the count of unread messages
  /// Unread messages are defined as messages that are not from the current user AND have not been marked as read
  /// This method will fetch the latest messages from the server before calculating the count
  /// Returns 0 if no unread messages are found or if there's an error
  Future<int> getUnreadMessageCount() async {
    try {
      final container = providerContainerMap[_parameters.clientInstanceKey]!;
      final localStorage = container.read(localStorageProvider(_parameters));
      
      // First load the latest messages from the server
      await _repository.getMessages();
      
      // Get all messages (now including the latest from server)
      final messages = localStorage.messagesDao.getMessages();
      
      // Get the set of read message IDs
      final readMessageIds = localStorage.messagesDao.getReadMessageIds();
      
      // Filter messages that are not from the current user AND have not been marked as read
      final unreadMessages = messages.where((message) => 
        !message.isMine && !readMessageIds.contains(message.id)
      ).toList();
      
      return unreadMessages.length;
    } catch (e) {
      // Return 0 if there's an error
      return 0;
    }
  }
  
  /// Marks all messages as read
  /// This will mark all currently stored messages as read,
  /// which will reset the unread message count to zero
  void markAllMessagesAsRead() {
    try {
      final container = providerContainerMap[_parameters.clientInstanceKey]!;
      final localStorage = container.read(localStorageProvider(_parameters));
      localStorage.messagesDao.markAllMessagesAsRead();
    } catch (e) {
      // Ignore errors
    }
  }

  /// Fetches the list of conversations from the server
  /// Returns an empty list if there's an error
  Future<List<ChatwootConversation>> getConversations() async {
    try {
      return await _repository.getConversations();
    } on ChatwootClientException catch (e) {
      callbacks?.onError?.call(e);
      return [];
    } catch (e) {
      callbacks?.onError?.call(ChatwootClientException(
          e.toString(), ChatwootClientExceptionType.GET_CONVERSATION_FAILED));
      return [];
    }
  }

  /// Creates an instance of [ChatwootClient] with the [baseUrl] of your chatwoot installation,
  /// [inboxIdentifier] for the targeted inbox. Specify custom user details using [user] and [callbacks] for
  /// handling chatwoot events. By default persistence is enabled, to disable persistence set [enablePersistence] as false
  static Future<ChatwootClient> create({
    required String baseUrl,
    required String inboxIdentifier,
    ChatwootUser? user,
    bool enablePersistence = true,
    ChatwootCallbacks? callbacks,
  }) async {
    if (enablePersistence) {
      await LocalStorage.openDB();
    }

    final chatwootParams = ChatwootParameters(
      clientInstanceKey: getClientInstanceKey(
        baseUrl: baseUrl,
        inboxIdentifier: inboxIdentifier,
        userIdentifier: user?.identifier,
      ),
      isPersistenceEnabled: enablePersistence,
      baseUrl: baseUrl,
      inboxIdentifier: inboxIdentifier,
      userIdentifier: user?.identifier,
    );

    final client = ChatwootClient._(
      chatwootParams,
      callbacks: callbacks,
      user: user,
    );

    client._init();

    return client;
  }

  static final _keySeparator = "|||";

  ///Create a chatwoot client instance key using the chatwoot client instance baseurl, inboxIdentifier
  ///and userIdentifier. Client instance keys are used to differentiate between client instances and their data
  ///(contact ([ChatwootContact]),conversation ([ChatwootConversation]) and messages ([ChatwootMessage]))
  ///
  /// Create separate [ChatwootClient] instances with same baseUrl, inboxIdentifier, userIdentifier and persistence
  /// enabled will be regarded as same therefore use same contact and conversation.
  static String getClientInstanceKey({
    required String baseUrl,
    required String inboxIdentifier,
    String? userIdentifier,
  }) {
    return "$baseUrl$_keySeparator$userIdentifier$_keySeparator$inboxIdentifier";
  }

  static Map<String, ProviderContainer> providerContainerMap = Map();

  ///Clears all persisted chatwoot data on device for a particular chatwoot client instance.
  ///See [getClientInstanceKey] on how chatwoot client instance are differentiated
  static Future<void> clearData({
    required String baseUrl,
    required String inboxIdentifier,
    String? userIdentifier,
  }) async {
    final clientInstanceKey = getClientInstanceKey(
      baseUrl: baseUrl,
      inboxIdentifier: inboxIdentifier,
      userIdentifier: userIdentifier,
    );
    providerContainerMap.putIfAbsent(
      clientInstanceKey,
      () => ProviderContainer(),
    );
    final container = providerContainerMap[clientInstanceKey]!;
    final params = ChatwootParameters(
      isPersistenceEnabled: true,
      baseUrl: "",
      inboxIdentifier: "",
      clientInstanceKey: "",
    );

    final localStorage = container.read(localStorageProvider(params));
    await localStorage.clear();

    localStorage.dispose();
    container.dispose();
    providerContainerMap.remove(clientInstanceKey);
  }

  /// Clears all persisted chatwoot data on device.
  static Future<void> clearAllData() async {
    providerContainerMap.putIfAbsent("all", () => ProviderContainer());
    final container = providerContainerMap["all"]!;
    final params = ChatwootParameters(
      isPersistenceEnabled: true,
      baseUrl: "",
      inboxIdentifier: "",
      clientInstanceKey: "",
    );

    final localStorage = container.read(localStorageProvider(params));
    await localStorage.clearAll();

    localStorage.dispose();
    container.dispose();
  }
}
