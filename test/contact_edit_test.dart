import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/contacts_controller.dart';
import 'package:itp_voice/controllers/edit_contact_controller.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/contact_response.dart';
import 'package:itp_voice/repo/base_requester.dart';
import 'package:itp_voice/repo/contacts_repo.dart';
import 'package:itp_voice/screens/edit_contact_screen.dart';

class _Contacts extends ContactsController {
  @override
  Future<void> fetchContacts(String offSet) async {}
}

class _Repo extends ContactsRepo {
  List<Object?>? saved;

  @override
  Future<bool> updateContact(
      dynamic id, String name, String notes, String phone, String email) async {
    saved = [id, name, notes, phone, email];
    return true;
  }
}

void main() {
  testWidgets(
      'edit a phone-only contact without changing its country code or label',
      (tester) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    Get.put(BaseRequester());
    Get.put<ContactsController>(_Contacts());
    final repo = _Repo();
    final contact = Contact(
      pk: 7,
      firstname: 'Alex',
      lastname: 'Chen',
      notes: 'Work',
      phone: '+44 20 7946 0123',
    );
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    Get.to(() => const EditContactScreen(), arguments: {'contact': contact});
    await tester.pumpAndSettle();
    expect(find.text('Email (optional)'), findsOneWidget);
    Get.find<EditContactController>().contactsRepo = repo;
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(repo.saved, [7, 'Alex Chen', 'Work', '+442079460123', '']);
  });
}
