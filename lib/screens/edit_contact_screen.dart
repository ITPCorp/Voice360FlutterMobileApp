import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/edit_contact_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/contact_response.dart';

class EditContactScreen extends StatefulWidget {
  const EditContactScreen({super.key});

  @override
  State<EditContactScreen> createState() => _EditContactScreenState();
}

class _EditContactScreenState extends State<EditContactScreen> {
  final EditContactController con = Get.put(EditContactController());
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  String _label = 'Mobile';

  @override
  void initState() {
    super.initState();
    final Contact c = con.contact ?? Contact();
    _firstName = TextEditingController(text: c.firstname ?? '');
    _lastName = TextEditingController(text: c.lastname ?? '');
    if (c.phone != null &&
        c.phone!.isNotEmpty &&
        con.contactFieldsData.isNotEmpty) {
      (con.contactFieldsData[0]['controller'] as TextEditingController).text =
          c.phone!;
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  void _save() {
    final c = con.contact;
    if (c != null) {
      c.firstname = _firstName.text.trim();
      c.lastname = _lastName.text.trim();
    }
    if (con.contactFieldsData.isNotEmpty) {
      con.contactFieldsData[0]['selectedLabel'] = con.contactsLabels
          .indexOf(_label)
          .clamp(0, con.contactsLabels.length - 1);
    }
    con.saveContact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit contact'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: GetBuilder<EditContactController>(
        builder: (_) {
          final phoneCtrl = con.contactFieldsData.isEmpty
              ? null
              : con.contactFieldsData[0]['controller'] as TextEditingController;
          final emailCtrl = con.emailFieldsData.isEmpty
              ? null
              : con.emailFieldsData[0]['controller'] as TextEditingController;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(V360Spacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: V360Avatar(
                    name: '${_firstName.text} ${_lastName.text}'
                            .trim()
                            .isEmpty
                        ? '?'
                        : '${_firstName.text} ${_lastName.text}',
                    size: 96,
                  ),
                ),
                const SizedBox(height: V360Spacing.s8),
                _label_('First name'),
                const SizedBox(height: V360Spacing.s2),
                TextField(
                  controller: _firstName,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'First name'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: V360Spacing.s4),
                _label_('Last name'),
                const SizedBox(height: V360Spacing.s2),
                TextField(
                  controller: _lastName,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Last name'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: V360Spacing.s5),
                _label_('Phone number'),
                const SizedBox(height: V360Spacing.s2),
                Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: DropdownButtonFormField<String>(
                        value: _label,
                        isDense: true,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: V360Spacing.s3,
                            vertical: V360Spacing.s3,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'Mobile', child: Text('Mobile')),
                          DropdownMenuItem(value: 'Work', child: Text('Work')),
                          DropdownMenuItem(value: 'Home', child: Text('Home')),
                          DropdownMenuItem(
                              value: 'Others', child: Text('Other')),
                        ],
                        onChanged: (v) =>
                            setState(() => _label = v ?? 'Mobile'),
                      ),
                    ),
                    const SizedBox(width: V360Spacing.s2),
                    Expanded(
                      child: TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: '(555) 123-4567',
                          prefixIcon: Icon(Icons.phone_outlined, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: V360Spacing.s5),
                _label_('Email'),
                const SizedBox(height: V360Spacing.s2),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'name@example.com',
                    prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: V360Spacing.s8),
                V360Button(
                  label: 'Save changes',
                  onPressed: _save,
                  fullWidth: true,
                  size: V360ButtonSize.lg,
                ),
                const SizedBox(height: V360Spacing.s6),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _label_(String text) => Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      );
}
