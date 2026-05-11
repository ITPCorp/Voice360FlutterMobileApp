import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/cache/cache_service.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/contact_response.dart';
import 'package:itp_voice/repo/contacts_repo.dart';
import 'package:itp_voice/widgets/custom_loader.dart';
import 'package:itp_voice/widgets/custom_toast.dart';

/// Owns the contacts list AND the search/autocomplete flow.
///
/// Two distinct lists live here:
///   - `_allContacts`   — the unfiltered, paginated full list backing the
///                        Contacts tab. Persisted to disk.
///   - `_searchResults` — the **transient** result list rendered while a
///                        search query is active. Never persisted.
///
/// The UI calls [getDataList] which returns whichever list is appropriate.
/// This separation kills the previous "search results duplicate into the
/// main list" class of bugs — search no longer mutates `_allContacts`.
///
/// Search uses a **request-id guard** so out-of-order responses from
/// keystroke-burst typing can't clobber a more recent query. Each new
/// request bumps `_searchRequestId`; only responses tagged with the latest
/// id are accepted.
class ContactsController extends GetxController {
  bool isContactsLoading = false;
  ContactsRepo repo = ContactsRepo();

  // -- Full list (paginated)
  List<Contact> _allContacts = [];
  // Kept for backwards-compat with the few places that read it directly.
  // Don't add to this from anywhere new — use getDataList() instead.
  List<Contact> get unfilteredData => _allContacts;

  // -- Search state
  TextEditingController searchController = TextEditingController();
  String _activeSearchQuery = '';
  List<Contact> _searchResults = const [];
  int _searchRequestId = 0;
  bool isSearching = false;

  RxInt conOffSet = 0.obs,
      totalPages = 0.obs,
      currentPage = 0.obs,
      totalCount = 0.obs;

  bool _hydratedFromCache = false;
  bool get hasCachedData => _hydratedFromCache;

  @override
  void onInit() {
    super.onInit();
    _hydrateFromCache();
  }

  void _hydrateFromCache() {
    if (!AppCache.instance.isReady) return;
    final cached = AppCache.instance.contacts.readAll();
    if (cached.isEmpty) return;
    _allContacts = cached;
    _hydratedFromCache = true;
    update();
  }

  /// Fetch a page of the full contacts list. Page 0 replaces the in-memory
  /// list atomically; later pages append. Never mutated by search.
  Future<void> fetchContacts(String offSet) async {
    if (offSet == '0') {
      conOffSet.value = 0;
      totalPages.value = 0;
      totalCount.value = 0;
      currentPage.value = 0;
      isContactsLoading = !_hydratedFromCache && _allContacts.isEmpty;
      update();
    }

    final res = await repo.getContacts(offSet);
    isContactsLoading = false;

    if (res is ContactResponse) {
      totalPages.value = res.totalPages ?? 0;
      totalCount.value = res.itemCount ?? 0;
      currentPage.value = currentPage.value + 1;
      conOffSet.value = conOffSet.value + 20;
      if (res.result != null) {
        final filtered = res.result!
            .where((c) => (c.firstname != null && c.firstname!.isNotEmpty))
            .toList();
        if (offSet == '0') {
          _allContacts = filtered;
        } else {
          // De-dupe on pk so re-fetches don't double rows.
          final seen = _allContacts.map((c) => c.pk).toSet();
          for (final c in filtered) {
            if (!seen.contains(c.pk)) _allContacts.add(c);
          }
        }
        if (AppCache.instance.isReady) {
          AppCache.instance.contacts.writeAll(_allContacts);
        }
      }
    }
    update();
  }

  /// Apply a server-side search for [query]. Tagged with a request id so
  /// stale responses are silently dropped.
  Future<void> searchContacts(String query) async {
    final myId = ++_searchRequestId;
    _activeSearchQuery = query;
    isSearching = true;
    update();

    final res = await repo.searchContacts('0', query);

    // Stale response — a newer query was issued after we kicked this off.
    // Drop the result on the floor. The newer call will update the UI.
    if (myId != _searchRequestId) return;
    // Query was cleared while waiting.
    if (_activeSearchQuery.isEmpty) return;

    isSearching = false;
    if (res is ContactResponse && res.result != null) {
      final filtered = res.result!
          .where((c) => (c.firstname != null && c.firstname!.isNotEmpty))
          .toList();
      // De-dupe just in case the backend returns the same pk twice.
      final seen = <int?>{};
      _searchResults = [
        for (final c in filtered)
          if (seen.add(c.pk)) c
      ];
    } else {
      _searchResults = const [];
    }
    update();
  }

  /// Cancel the active search and reset to the full list. Idempotent.
  void clearSearch() {
    _searchRequestId++; // invalidate any in-flight searches
    _activeSearchQuery = '';
    _searchResults = const [];
    isSearching = false;
    searchController.clear();
    update();
  }

  Future<void> deleteContact(int? id) async {
    if (id == null) return;
    Get.back();
    CustomLoader.showLoader();
    final res = await repo.deleteContact(id);
    Get.back();

    if (res is String) {
      CustomToast.showToast(res, true);
    } else {
      Get.back();
      _allContacts.removeWhere((c) => c.pk == id);
      _searchResults =
          _searchResults.where((c) => c.pk != id).toList(growable: false);
      if (AppCache.instance.isReady) {
        AppCache.instance.contacts.remove(id);
      }
      update();
    }
  }

  /// What the UI renders. Active search → results; otherwise → full list.
  /// A trailing client-side filter still runs on the full-list path so that
  /// users see instant filtering before the network search lands.
  List<Contact> getDataList() {
    final query = searchController.text.trim();
    if (query.isEmpty) return _allContacts;

    // Active server search — render those results.
    if (_activeSearchQuery == query) return _searchResults;

    // Server hasn't responded yet for the current keystroke — show an
    // instant client-side filter on whatever full-list data we already have.
    final lc = query.toLowerCase();
    return _allContacts.where((c) {
      final name = '${c.firstname ?? ''} ${c.lastname ?? ''}'.toLowerCase();
      final phone = (c.phone ?? '').toLowerCase();
      final email = (c.email ?? '').toLowerCase();
      return name.contains(lc) || phone.contains(lc) || email.contains(lc);
    }).toList(growable: false);
  }
}
