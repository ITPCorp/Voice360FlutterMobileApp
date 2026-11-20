import 'package:itp_voice/helpers/page_refresh.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/helpers/group_chat.dart';
import 'package:itp_voice/locator.dart';
import 'package:itp_voice/models/get_message_threads_response_model/get_message_threads_response_model.dart';
import 'package:itp_voice/repo/messages_repo.dart';
import 'package:itp_voice/cache/cache_service.dart';
import 'package:itp_voice/services/contact_resolver.dart';
import 'package:itp_voice/services/global_socket_service.dart';
import 'package:itp_voice/services/numbers_service.dart';
import 'package:itp_voice/services/threads_cache.dart';

class MessagesController extends GetxController {
  MessagesRepo repo = MessagesRepo();

  List<MessageThreads> get threads =>
      _query.value.isEmpty ? allThreads : filteredThreads;
  RxList<MessageThreads> allThreads = <MessageThreads>[].obs;
  RxList<MessageThreads> filteredThreads = <MessageThreads>[].obs;

  TextEditingController searchController = TextEditingController();

  List<String> get numbers => locator<NumbersService>().chatNumbers;
  Rxn<String> selectedNumberRx = Rxn<String>();
  String? get selectedNumber => selectedNumberRx.value;
  set selectedNumber(String? v) => selectedNumberRx.value = v;

  final _query = ''.obs;
  final refreshing = false.obs;
  int _generation = 0;
  String? _loadedNumber;
  RxBool isloading = false.obs;

  /// True while the bottom-of-list "load more" request is in flight.
  final loadFailed = false.obs;
  RxBool isLoadingMore = false.obs;

  /// Offset for the NEXT page to request. Reset to 0 on refresh / number-swap.
  int _nextOffset = 0;

  /// True when the server returned fewer than [MessagesRepo.kThreadsPageLimit]
  /// on the most recent page — no more pages to fetch.
  bool _reachedEnd = false;
  bool get hasMore => !_reachedEnd;

  bool _hydratedFromCache = false;

  /// Subscription to the global notification socket — bumps the threads list
  /// when an SMS event arrives so previews and unread counts stay live.
  StreamSubscription<GlobalSocketEvent>? _socketSub;
  Timer? _socketDebounce;

  /// Read whatever threads we persisted last time and render them. Cheap;
  /// runs synchronously off the open Hive box.
  void hydrateFromCache() {
    if (!AppCache.instance.isReady || _hydratedFromCache) return;
    final from = selectedNumber ?? '';
    if (from.isEmpty) return;
    final cached = AppCache.instance.threads.read(from);
    if (cached.isEmpty) return;
    allThreads.assignAll(cached);
    locator<ThreadsCache>().prime(from, cached);
    _hydratedFromCache = true;
  }

  /// Refresh — fetch the first page, replace the list.
  loadThreads() async {
    final from = selectedNumber ?? '';
    final generation = ++_generation;
    if (from != _loadedNumber) {
      _loadedNumber = from;
      _hydratedFromCache = false;
      allThreads.clear();
      filteredThreads.clear();
      _nextOffset = 0;
      _reachedEnd = false;
    }
    isLoadingMore.value = false;
    hydrateFromCache();
    filterThreads();
    // Show shimmer only when nothing is on screen.
    isloading.value = allThreads.isEmpty;
    refreshing.value = allThreads.isNotEmpty;

    // No texting number assigned: there is nothing to ask the API for (the
    // URL without a number is a 404), so show the empty state.
    if (from.isEmpty) {
      loadFailed.value = false;
      allThreads.clear();
      _reachedEnd = true;
      isloading.value = false;
      return;
    }

    final res = await repo.getMessageThreads(from, offset: 0);
    if (generation != _generation || from != selectedNumber) return;
    refreshing.value = false;
    loadFailed.value = res is! GetMessageThreadsResponseModel;
    if (res is GetMessageThreadsResponseModel) {
      final fresh = res.result?.messageThreads ?? const <MessageThreads>[];
      allThreads.assignAll(mergeFirstPage(fresh, allThreads, (t) => t.pk,
          hasMore: fresh.length == MessagesRepo.kThreadsPageLimit));
      filterThreads();
      _nextOffset = allThreads.length;
      _reachedEnd = fresh.length < MessagesRepo.kThreadsPageLimit;
      // In-memory cache for the chat screen's "does a thread exist?" lookup.
      if (from.isNotEmpty) {
        locator<ThreadsCache>().prime(from, allThreads.toList());
        // Persist to disk so the next cold start renders instantly.
        if (AppCache.instance.isReady) {
          AppCache.instance.threads.write(from, allThreads.toList());
        }
      }
    }

    isloading.value = false;
  }

  /// Fetch the next page and append to the list. Safe to call multiple
  /// times — concurrent calls coalesce (only one request in flight) and a
  /// no-op once [hasMore] is false.
  Future<void> loadMoreThreads() async {
    if (_reachedEnd ||
        isLoadingMore.value ||
        refreshing.value ||
        isloading.value) {
      return;
    }
    final from = selectedNumber ?? '';
    if (from.isEmpty) return;

    final generation = _generation;
    isLoadingMore.value = true;
    try {
      final res = await repo.getMessageThreads(from, offset: _nextOffset);
      if (generation != _generation || from != selectedNumber) return;
      if (res is GetMessageThreadsResponseModel) {
        final more = res.result?.messageThreads ?? const <MessageThreads>[];
        if (more.isEmpty) {
          _reachedEnd = true;
        } else {
          final seen = allThreads.map((t) => t.pk).toSet();
          allThreads.addAll(more.where((t) => seen.add(t.pk)));
          filterThreads();
          _nextOffset += more.length;
          if (more.length < MessagesRepo.kThreadsPageLimit) {
            _reachedEnd = true;
          }
          // Persist the now-larger snapshot so the next cold start is bigger.
          if (AppCache.instance.isReady) {
            AppCache.instance.threads.write(from, allThreads.toList());
          }
          locator<ThreadsCache>().prime(from, allThreads.toList());
        }
      }
    } finally {
      if (generation == _generation) isLoadingMore.value = false;
    }
  }

  /// Search by any participant's number or resolved name, so a group
  /// matches on every member, not only the first one.
  filterThreads() {
    final query = searchController.text.trim().toLowerCase();
    _query.value = query;
    if (query.isEmpty) return;
    final queryDigits = query.replaceAll(RegExp(r'\D'), '');
    final matches = <MessageThreads>[];
    for (MessageThreads thread in allThreads) {
      final others = otherMembers(ContactResolver.membersOfThread(thread));
      final hit = others.any((m) =>
          m.number.contains(searchController.text) ||
          (queryDigits.isNotEmpty &&
              m.number.replaceAll(RegExp(r'\D'), '').contains(queryDigits)) ||
          (query.isNotEmpty &&
              (m.fullName ?? '').toLowerCase().contains(query)));
      if (hit) matches.add(thread);
    }
    filteredThreads.assignAll(matches);
  }

  @override
  void onInit() async {
    if (numbers.isEmpty) {
      await locator<NumbersService>().getUpdatedNumbersList();
    }
    if (numbers.isNotEmpty) {
      selectedNumber = numbers[0];
    }
    _subscribeToGlobalSocket();
    loadThreads();
    super.onInit();
  }

  @override
  void onClose() {
    _socketDebounce?.cancel();
    _socketSub?.cancel();
    super.onClose();
  }

  /// Refresh the threads list whenever an SMS arrives on the global socket.
  /// Debounced so a burst of events doesn't spam the API.
  void _subscribeToGlobalSocket() {
    _socketSub?.cancel();
    final socket = locator<GlobalSocketService>();
    socket.connect();
    _socketSub = socket.events.listen((event) {
      if (!event.isAnySms) return;
      _socketDebounce?.cancel();
      _socketDebounce = Timer(const Duration(milliseconds: 600), () {
        loadThreads();
      });
    });
  }
}
