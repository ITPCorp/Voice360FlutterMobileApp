import 'package:floating_bottom_bar/animated_bottom_navigation_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/locator.dart';
import 'package:itp_voice/models/get_message_threads_response_model/get_message_threads_response_model.dart';
import 'package:itp_voice/repo/messages_repo.dart';
import 'package:itp_voice/cache/cache_service.dart';
import 'package:itp_voice/services/numbers_service.dart';
import 'package:itp_voice/services/threads_cache.dart';
import 'package:itp_voice/widgets/app_button.dart';
import 'package:itp_voice/widgets/app_textfield.dart';
import 'package:itp_voice/widgets/phone_number_field.dart';

import '../widgets/custom_toast.dart';

class MessagesController extends GetxController {
  MessagesRepo repo = MessagesRepo();

  List<MessageThreads> get threads =>
      filteredThreads.isEmpty ? allThreads.toList() : filteredThreads.toList();
  RxList<MessageThreads> allThreads = <MessageThreads>[].obs;
  RxList<MessageThreads> filteredThreads = <MessageThreads>[].obs;

  TextEditingController searchController = TextEditingController();

  List<String> get numbers => locator<NumbersService>().chatNumbers;
  Rxn<String> selectedNumberRx = Rxn<String>();
  String? get selectedNumber => selectedNumberRx.value;
  set selectedNumber(String? v) => selectedNumberRx.value = v;

  RxBool isloading = false.obs;

  /// True while the bottom-of-list "load more" request is in flight.
  RxBool isLoadingMore = false.obs;

  /// Offset for the NEXT page to request. Reset to 0 on refresh / number-swap.
  int _nextOffset = 0;

  /// True when the server returned fewer than [MessagesRepo.kThreadsPageLimit]
  /// on the most recent page — no more pages to fetch.
  bool _reachedEnd = false;
  bool get hasMore => !_reachedEnd;

  bool _hydratedFromCache = false;

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
    hydrateFromCache();
    // Show shimmer only when nothing is on screen.
    isloading.value = allThreads.isEmpty;
    filteredThreads.clear();
    searchController.clear();

    _nextOffset = 0;
    _reachedEnd = false;

    final res = await repo.getMessageThreads(from, offset: 0);
    if (res is GetMessageThreadsResponseModel) {
      final fresh = res.result?.messageThreads ?? const <MessageThreads>[];
      allThreads.assignAll(fresh);
      _nextOffset = fresh.length;
      _reachedEnd = fresh.length < MessagesRepo.kThreadsPageLimit;
      // In-memory cache for the chat screen's "does a thread exist?" lookup.
      if (from.isNotEmpty) {
        locator<ThreadsCache>().prime(from, fresh);
        // Persist to disk so the next cold start renders instantly.
        if (AppCache.instance.isReady) {
          AppCache.instance.threads.write(from, fresh);
        }
      }
    }

    isloading.value = false;
  }

  /// Fetch the next page and append to the list. Safe to call multiple
  /// times — concurrent calls coalesce (only one request in flight) and a
  /// no-op once [hasMore] is false.
  Future<void> loadMoreThreads() async {
    if (_reachedEnd || isLoadingMore.value) return;
    final from = selectedNumber ?? '';
    if (from.isEmpty) return;

    isLoadingMore.value = true;
    try {
      final res = await repo.getMessageThreads(from, offset: _nextOffset);
      if (res is GetMessageThreadsResponseModel) {
        final more = res.result?.messageThreads ?? const <MessageThreads>[];
        if (more.isEmpty) {
          _reachedEnd = true;
        } else {
          allThreads.addAll(more);
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
      isLoadingMore.value = false;
    }
  }

  filterThreads() {
    isloading.value = true;
    final matches = <MessageThreads>[];
    for (MessageThreads thread in allThreads) {
      if (thread.participants!
          .where((element) => element.isSelf != true)
          .toList()[0]
          .number!
          .contains(searchController.text)) {
        matches.add(thread);
      }
    }
    filteredThreads.assignAll(matches);
    isloading.value = false;
  }

  sendNewMessage(BuildContext context) async {
    final res = await showDialog(
      context: context,
      builder: (childContext) => AddThreadDialog(),
    );
    print(res);
    if (res is List) {
      if (selectedNumber == null || selectedNumber!.isEmpty) {
        CustomToast.showToast(
          'Please select a number to send from first',
          true,
        );
        return;
      }
      isloading.value = true;
      final numberString = "{\"list\": [\"${res[0]}\"]}";
      await repo.sendMessage(selectedNumber!, res[1], numberString);
      await loadThreads();
    }
  }

  @override
  void onInit() async {
    if (numbers.isEmpty) {
      await locator<NumbersService>().getUpdatedNumbersList();
    }
    if (numbers.isNotEmpty) {
      selectedNumber = numbers[0];
    }
    loadThreads();
    super.onInit();
  }
}

class AddThreadDialog extends StatelessWidget {
  const AddThreadDialog({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    String code = "1";
    TextEditingController number = TextEditingController();
    String message = "";
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "To",
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              PhoneNumberField(
                hint: "XXXXXXXXXX",
                textController: number,
                onChanged: (value) {
                  code = value;
                },
              ),
              const SizedBox(height: 15),
              Text(
                "Message",
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              AppTextField(
                hint: "Enter message",
                onChanged: (value) => message = value,
              ),
              const SizedBox(height: 10),
              GestureDetector(
                  onTap: () => Navigator.of(context).pop([
                        "+${code}${number.text}",
                        message,
                      ]),
                  child: AppButton(
                    text: "Send",
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
