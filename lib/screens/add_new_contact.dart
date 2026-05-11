import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/add_new_contact_controller.dart';
import 'package:itp_voice/design/v360.dart';

class AddNewContactScreen extends StatefulWidget {
  const AddNewContactScreen({super.key});

  @override
  State<AddNewContactScreen> createState() => _AddNewContactScreenState();
}

class _AddNewContactScreenState extends State<AddNewContactScreen> {
  final AddNewContactController con = Get.put(AddNewContactController());
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  String _label = 'Mobile';

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    if (args is String) {
      // Pre-fill phone number from "Save as contact" dialer action
      if (con.contactFieldsData.isNotEmpty) {
        (con.contactFieldsData[0]['controller'] as TextEditingController)
            .text = args;
      }
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  void _save() {
    final fullName = '${_firstName.text.trim()} ${_lastName.text.trim()}'.trim();
    con.fullNameController.text = fullName;
    if (con.contactFieldsData.isNotEmpty) {
      con.contactFieldsData[0]['selectedLabel'] =
          con.contactsLabels.indexOf(_label).clamp(0, con.contactsLabels.length - 1);
    }
    con.saveContact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New contact'),
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
      body: GetBuilder<AddNewContactController>(
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
                    name:
                        '${_firstName.text} ${_lastName.text}'.trim().isEmpty
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
                          DropdownMenuItem(value: 'Mobile', child: Text('Mobile')),
                          DropdownMenuItem(value: 'Work', child: Text('Work')),
                          DropdownMenuItem(value: 'Home', child: Text('Home')),
                          DropdownMenuItem(value: 'Others', child: Text('Other')),
                        ],
                        onChanged: (v) => setState(() => _label = v ?? 'Mobile'),
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
                  label: 'Save contact',
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
