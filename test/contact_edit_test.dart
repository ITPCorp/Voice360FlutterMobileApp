import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/contacts_controller.dart';
import 'package:itp_voice/controllers/add_new_contact_controller.dart';
import 'package:itp_voice/helpers/contact_phone.dart';
import 'package:itp_voice/screens/add_new_contact.dart';
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
  String? validated;
  @override
  Future<bool> validatePhoneNumber(String phone) async {
    validated = phone;
    return true;
  }

  @override
  Future<bool> createContact(
      String name, String notes, String phone, String email) async {
    saved = [name, notes, phone, email];
    return true;
  }

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
  test('new contact numbers respect explicitly entered calling codes', () {
    expect(newContactPhone('1 (202) 555-0148'), '+12025550148');
    expect(newContactPhone('+44 20 7946 0123'), '+442079460123');
    expect(newContactPhone('+49 1234 5678'), '+4912345678');
    expect(displayNewContactPhone('+49 1234 5678'), '+49 1234 5678');
    expect(newContactPhone('310'), '310');
  });

  testWidgets('new contact formats, validates and saves a local number as +1',
      (tester) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    Get.put(BaseRequester());
    Get.put<ContactsController>(_Contacts());
    final repo = _Repo();
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    Get.to(() => const AddNewContactScreen());
    await tester.pumpAndSettle();
    Get.find<AddNewContactController>().contactsRepo = repo;
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Test');
    await tester.enterText(fields.at(2), '2025550148');
    await tester.ensureVisible(fields.at(3));
    await tester.tap(fields.at(3));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fields.at(2)).controller!.text,
        '+1 (202) 555-0148');
    await tester.ensureVisible(find.text('Save contact'));
    await tester.tap(find.text('Save contact'));
    await tester.pumpAndSettle();
    expect(repo.validated, '+12025550148');
    expect(repo.saved, ['Test', 'Mobile', '+12025550148', '']);
  });

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
