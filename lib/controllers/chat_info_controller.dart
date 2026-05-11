import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import '../cache/cache_service.dart';
import '../models/get_contacts_reponse_model/contact_response.dart';
import '../models/get_thread_messages_response_model/get_thread_messages_response_model.dart'
    as tm;
import '../repo/contacts_repo.dart';
import '../services/contact_resolver.dart';
import '../widgets/custom_toast.dart';
import 'contacts_controller.dart';

class ChatInfoController extends GetxController {
  TextEditingController fullNameController = TextEditingController();
  ContactsController contactsController = Get.put(ContactsController());
  String initialName = '';
  int? pk;

  /// The phone number for this conversation — either pulled directly from
  /// the legacy String argument, or from a `{phone, participantContact}` map.
  late final String phone;

  /// Server-embedded participant contact, if the chat screen passed one
  /// through. Lets us label and link the (i) view even when the contact
  /// isn't in the local contacts cache yet.
  tm.ParticipantContact? _seedFromParticipant;

  ContactsRepo repo = ContactsRepo();
  RxBool isLoading = false.obs;
  RxInt limit = 0.obs, offSet = 0.obs, totalContacts = 0.obs;

  /// The matched contact (when [pk] is non-null). Populated from cache
  /// first (instant) and then from a fresh fetch on `onInit`.
  Contact? linkedContact;
  bool get isLinked => pk != null && linkedContact != null;

  ChatInfoController() {
    final args = Get.arguments;
    if (args is String) {
      phone = args;
    } else if (args is Map) {
      phone = (args['phone'] ?? '').toString();
      final pc = args['participantContact'];
      if (pc is tm.ParticipantContact) _seedFromParticipant = pc;
    } else {
      phone = '';
    }
  }

  addContact() async {
    if (fullNameController.text.isEmpty || fullNameController.text == null) {
      CustomToast.showToast("Please enter contact name", true);

      return;
    }
    isLoading.value = true;
    try {
      var res = await repo.createContact(fullNameController.text, 'work', phone, '');
      if (res.runtimeType == String) {
        CustomToast.showToast(res, true);
      }
      if (res.runtimeType == null) {
        CustomToast.showToast("Something went wrong", true);
      }
      if (res) {
        CustomToast.showToast("New contact created successfully", false);

        contactsController.fetchContacts('0',);
        try {
          final res = await repo.getContacts('0',);
          if (res.runtimeType == ContactResponse) {
            for (Contact contact in (res as ContactResponse).result ?? <Contact>[]) {
              if (contact.phone == phone) {
                initialName = contact.firstname ?? '';
                fullNameController.text = contact.firstname ?? "";
                pk = contact.pk;
              }
            }
          }
        } catch (e) {
          null;
        }
      }
    } catch (e) {
      CustomToast.showToast("Something went wrong", true);
    }
    isLoading.value = false;
  }

  updateContact() async {
    if (fullNameController.text.isEmpty || fullNameController.text == null) {
      CustomToast.showToast("Please enter contact name", true);

      return;
    }
    isLoading.value = true;
    try {
      var res = await repo.updateContact(pk, fullNameController.text, 'work', phone, '');
      if (res.runtimeType == String) {
        CustomToast.showToast(res, true);
      }
      if (res.runtimeType == null) {
        CustomToast.showToast("Something went wrong", true);
      }
      if (res) {
        CustomToast.showToast("Updated Contact successfully", false);

        contactsController.fetchContacts('0',);
        try {
          final res = await repo.getContacts('0');
          if (res.runtimeType == ContactResponse) {
            for (Contact contact in (res as ContactResponse).result ?? <Contact>[]) {
              if (contact.phone == phone) {
                initialName = contact.firstname ?? '';
                fullNameController.text = contact.firstname ?? "";
                pk = contact.pk;
              }
            }
          }
        } catch (e) {
          null;
        }
      }
    } catch (e) {
      CustomToast.showToast("Something went wrong", true);
    }
    isLoading.value = false;
  }

  @override
  void onInit() async {
    super.onInit();
    // 1. Synthesise from the passed-in participant contact (instant; no I/O).
    //    The chat thread already knew the server matched this number to a
    //    CRM contact — there's no point making the user wait for a cache or
    //    network round-trip to surface the same info.
    _hydrateFromParticipantContact();
    // 2. Hydrate from local cache by phone — promotes the synth into a full
    //    Contact (with notes, address, etc.) when the row is in the cache.
    _hydrateFromCache();
    // 3. Background: refresh from the server so any newly-added contact
    //    gets picked up even if cache is stale.
    isLoading.value = true;
    try {
      final res = await repo.getContacts("0");
      if (res is ContactResponse) {
        _matchAgainstList(res.result ?? <Contact>[]);
      }
    } catch (_) {
      // Network failure is OK — we still have the cache / participant match.
    }
    isLoading.value = false;
  }

  /// If the chat screen passed us a server-embedded participant contact,
  /// synthesise a [Contact] with the few fields we have so the view can
  /// render the "linked" UI immediately. The full Contact (with notes,
  /// address, etc.) will be promoted in by [_hydrateFromCache] or the
  /// background refresh.
  void _hydrateFromParticipantContact() {
    final p = _seedFromParticipant;
    if (p == null) return;
    if (p.pk == null) return;
    final c = Contact()
      ..pk = p.pk
      ..firstname = p.firstname
      ..lastname = p.lastname
      ..phone = p.phone ?? phone
      ..email = p.email;
    linkedContact = c;
    pk = p.pk;
    final name = ('${p.firstname ?? ''} ${p.lastname ?? ''}').trim();
    initialName = name.isNotEmpty ? name : (p.firstname ?? '');
    fullNameController.text = initialName;
  }

  void _hydrateFromCache() {
    if (!AppCache.instance.isReady) return;
    _matchAgainstList(AppCache.instance.contacts.readAll());
  }

  /// Look for a contact whose phone matches [phone]. First exact match wins.
  /// Uses digits-only suffix comparison so "+1 555 1234" and "5551234" pair.
  void _matchAgainstList(List<Contact> list) {
    final wanted = phone.replaceAll(RegExp(r'\D'), '');
    if (wanted.isEmpty) return;
    for (final c in list) {
      final candidate = (c.phone ?? '').replaceAll(RegExp(r'\D'), '');
      if (candidate.isEmpty) continue;
      if (candidate == wanted ||
          candidate.endsWith(wanted) ||
          wanted.endsWith(candidate)) {
        linkedContact = c;
        pk = c.pk;
        final name = ('${c.firstname ?? ''} ${c.lastname ?? ''}').trim();
        initialName = name.isNotEmpty ? name : (c.firstname ?? '');
        fullNameController.text = initialName;
        return;
      }
    }
  }

  /// Convenience for the view: a display name resolved via the same chain
  /// the rest of the app uses. Lets the header show "Jane Doe" even when
  /// the link hasn't fully populated yet.
  String displayName() {
    if (linkedContact != null) {
      final name =
          ('${linkedContact!.firstname ?? ''} ${linkedContact!.lastname ?? ''}')
              .trim();
      if (name.isNotEmpty) return name;
    }
    return ContactResolver.resolveByPhone(phone, fallback: phone);
  }
}
