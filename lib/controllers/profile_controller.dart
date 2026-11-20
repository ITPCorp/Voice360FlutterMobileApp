import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:itp_voice/models/user_profile_model/result.dart';
import 'package:itp_voice/models/user_profile_model/user_profile.dart';
import 'package:itp_voice/repo/auth_repo.dart';
import 'package:itp_voice/repo/shares_preference_repo.dart';

class ProfileController extends GetxController {
  @override
  void onInit() {
    final cached = SharedPreferencesMethod.getUserData();
    if (cached != null) {
      _show(Profile(
          firstname: cached.firstname,
          lastname: cached.lastname,
          email: cached.email,
          mobile: cached.mobile));
    }
    fetchUserProfile();
    super.onInit();
  }

  RxBool isloading = false.obs;
  final loadFailed = false.obs;
  Profile? userProfile;
  TextEditingController nameController = TextEditingController();
  TextEditingController emailController = TextEditingController(text: '');
  TextEditingController mobileController = TextEditingController(text: '');

  TextEditingController firstNameController = TextEditingController();
  TextEditingController lastNameController = TextEditingController();
  AuthRepo repo = AuthRepo();
  String phoneCode = "";
  void _show(Profile profile) {
    userProfile = profile;
    nameController.text = [profile.firstname, profile.lastname]
        .whereType<String>()
        .join(' ')
        .trim();
    emailController.text = profile.email ?? '';
    mobileController.text = profile.mobile?.toString() ?? '';
  }

  fetchUserProfile() async {
    isloading.value = true;

    final res = await repo.getProfile();
    loadFailed.value = res is! UserProfile || res.profile == null;
    if (res is UserProfile && res.profile != null) _show(res.profile!);

    isloading.value = false;
  }
}
