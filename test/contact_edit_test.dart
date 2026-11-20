import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/contacts_controller.dart';
import 'package:itp_voice/controllers/base_screen_controller.dart';
import 'package:itp_voice/locator.dart';
import 'package:itp_voice/screens/contact_details_screen.dart';
import 'package:itp_voice/controllers/edit_contact_controller.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/contact_response.dart';
import 'package:itp_voice/repo/base_requester.dart';
import 'package:itp_voice/repo/contacts_repo.dart';
import 'package:itp_voice/screens/edit_contact_screen.dart';

class _Contacts extends ContactsController {
  @override
  Future<void> fetchContacts(String offSet) async {}
}

class _Home extends BaseScreenController {
  @override
  // No SIP session is needed to view a contact.
  // ignore: must_call_super
  void onInit() {}
  @override
  void onReady() {}
}

class _Repo extends ContactsRepo {
  bool deleteSucceeds = false;

  @override
  Future<bool> deleteContact(dynamic id) async => deleteSucceeds;

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
      'failed deletion keeps contact details open and success returns once',
      (tester) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    setupLocator();
    addTearDown(locator.reset);
    final repo = _Repo();
    Get.put(BaseRequester());
    Get.put<BaseScreenController>(_Home());
    Get.put<ContactsController>(_Contacts()..repo = repo);
    await tester.pumpWidget(
        const GetMaterialApp(home: Scaffold(body: Text('Contacts home'))));
    Get.to(() => const ContactDetailsScreen(), arguments: {
      'contact': Contact(pk: 7, firstname: 'Alex', phone: '+12025550101')
    });
    await tester.pumpAndSettle();

    Future<void> delete() async {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete contact'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
    }

    await delete();
    expect(find.byType(ContactDetailsScreen), findsOneWidget);
    expect(
        find.text('Could not delete this contact. Try again.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    repo.deleteSucceeds = true;
    await delete();
    expect(find.text('Contacts home'), findsOneWidget);
  });

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
