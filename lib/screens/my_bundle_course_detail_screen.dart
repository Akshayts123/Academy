// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:academy_app/models/common_functions.dart';
import 'package:academy_app/models/course_db_model.dart';
import 'package:academy_app/models/lesson.dart';
import 'package:academy_app/models/section_db_model.dart';
import 'package:academy_app/models/video_db_model.dart';
import 'package:academy_app/providers/database_helper.dart';
import 'package:academy_app/providers/my_bundles.dart';
import 'package:academy_app/widgets/app_bar_two.dart';
import 'package:academy_app/widgets/custom_text.dart';
import 'package:academy_app/widgets/forum_tab_widget.dart';
import 'package:academy_app/widgets/live_class_tab_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:share/share.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants.dart';
import '../providers/shared_pref_helper.dart';
import '../widgets/from_network.dart';
import '../widgets/from_youtube.dart';
import 'course_detail_screen.dart';
import 'file_data_screen.dart';
import 'vimeo_iframe.dart';
import 'webview_screen.dart';
import 'webview_screen_iframe.dart';

class MyBundleCourseDetailScreen extends StatefulWidget {
  static const routeName = '/my-bundle-course-details';
  final int bundleId;
  final int courseId;
  final int len;
  const MyBundleCourseDetailScreen(
      {Key? key,
      required this.bundleId,
      required this.courseId,
      required this.len})
      : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _MyBundleCourseDetailScreenState createState() =>
      _MyBundleCourseDetailScreenState();
}

class _MyBundleCourseDetailScreenState extends State<MyBundleCourseDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ScrollController _scrollController;
  // late bool fixedScroll;

  var _isInit = true;
  var _isLoading = false;
  int? selected;
  dynamic myLoadedCourse;
  dynamic sections;

  dynamic liveClassStatus;
  dynamic courseForumStatus;
  dynamic data;
  Lesson? _activeLesson;

  final ReceivePort _port = ReceivePort();
  String buttonText = "Download";
  String downloadId = "";

  dynamic path;
  dynamic fileName;
  dynamic lessonId;
  dynamic courseId;
  dynamic sectionId;
  dynamic courseTitle;
  dynamic sectionTitle;
  dynamic thumbnail;

  @override
  void initState() {
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    _tabController = TabController(length: widget.len, vsync: this);
    _tabController.addListener(_smoothScrollToTop);
    super.initState();
    addonStatus('live-class');
    addonStatus('forum');
    bindBackgroundIsolate();
    FlutterDownloader.registerCallback(downloadCallback);
  }

  static void downloadCallback(
      String id, DownloadTaskStatus status, int progress) {
    final SendPort? send =
        IsolateNameServer.lookupPortByName('downloader_send_port');
    send!.send([id, status, progress]);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  _scrollListener() {
    // if (fixedScroll) {
    //   _scrollController.jumpTo(0);
    // }
  }

  _smoothScrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(microseconds: 300),
      curve: Curves.ease,
    );

    // setState(() {
    //   fixedScroll = _tabController.index == 1;
    // });
  }

  void unbindBackgroundIsolate() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
  }

  void bindBackgroundIsolate() {
    bool isSuccess = IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');
    if (!isSuccess) {
      unbindBackgroundIsolate();
      bindBackgroundIsolate();
      return;
    }
    _port.listen((dynamic data) async {
      // DownloadTaskStatus status = data[1];
      final status = DownloadTaskStatus(data[1] as int);
      if (status == DownloadTaskStatus.complete) {
        await DatabaseHelper.instance.addVideo(
          VideoModel(
              title: fileName,
              path: path,
              lessonId: lessonId,
              courseId: courseId,
              sectionId: sectionId,
              courseTitle: courseTitle,
              sectionTitle: sectionTitle,
              thumbnail: thumbnail,
              downloadId: downloadId),
        );
        var val = await DatabaseHelper.instance.courseExists(courseId);
        if (val != true) {
          await DatabaseHelper.instance.addCourse(
            CourseDbModel(
                courseId: courseId,
                courseTitle: courseTitle,
                thumbnail: thumbnail),
          );
        }
        var sec = await DatabaseHelper.instance.sectionExists(sectionId);
        if (sec != true) {
          await DatabaseHelper.instance.addSection(
            SectionDbModel(
                courseId: courseId,
                sectionId: sectionId,
                sectionTitle: sectionTitle),
          );
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    if (_isInit) {
      setState(() {
        _isLoading = true;
      });
      Provider.of<MyBundles>(context, listen: false)
          .fetchCourse(widget.bundleId, widget.courseId)
          .then((_) {
        setState(() {
          myLoadedCourse = Provider.of<MyBundles>(context, listen: false).items;
        });
      });

      Provider.of<MyBundles>(context, listen: false)
          .fetchCourseSections(widget.courseId)
          .then((_) {
        setState(() {
          sections =
              Provider.of<MyBundles>(context, listen: false).sectionItems;
          _isLoading = false;
          _activeLesson = sections.first.mLesson!.first;
        });
      });
    }
    _isInit = false;
    super.didChangeDependencies();
  }

  void _initDownload(
      Lesson lesson, myCourseId, coTitle, coThumbnail, secTitle, secId) async {
    // print(lesson.videoTypeWeb);
    if (lesson.videoTypeWeb == 'YouTube') {
      CommonFunctions.showSuccessToast(
          'This video format is not supported for download.');
    } else if (lesson.videoTypeWeb == 'Vimeo') {
      CommonFunctions.showSuccessToast(
          'This video format is not supported for download.');
    } else {
      var les = await DatabaseHelper.instance.lessonExists(lesson.id);
      if (les != true) {
        PermissionStatus permissionStatus = await Permission.storage.request();
        if (permissionStatus != PermissionStatus.granted) return;
        Directory directory;
        directory = (await getApplicationSupportDirectory());
        String dirName = "aca/.content";
        String contentName = lesson.title.toString();
        Directory file = Directory("${directory.path}/$dirName");
        file.createSync(recursive: true);
        File nomedia = File("${directory.path}/$dirName/.nomedia");
        // print(nomedia);
        if (!nomedia.existsSync()) nomedia.createSync(recursive: true);
        downloadId = (await FlutterDownloader.enqueue(
            url: lesson.videoUrlWeb.toString(),
            savedDir: "${directory.path}/$dirName",
            requiresStorageNotLow: true,
            showNotification: true,
            openFileFromNotification: false,
            fileName: contentName))!;
        setState(() {
          path = "${directory.path}/$dirName";
          fileName = contentName;
          lessonId = lesson.id;
          courseId = myCourseId;
          sectionId = secId;
          courseTitle = coTitle;
          sectionTitle = secTitle;
          thumbnail = coThumbnail;
          buttonText = "Downloading...";
        });
      } else {
        CommonFunctions.showSuccessToast('Video was downloaded already.');
      }
    }
  }

  Future<void> addonStatus(String identifier) async {
    var url = '$BASE_URL/api/addon_status?unique_identifier=$identifier';
    final response = await http.get(Uri.parse(url));
    if (identifier == 'live-class') {
      setState(() {
        liveClassStatus = json.decode(response.body)['status'];
      });
    } else if (identifier == 'forum') {
      setState(() {
        courseForumStatus = json.decode(response.body)['status'];
      });
    }
  }

  void lessonAction(Lesson lesson) async {
    if (lesson.lessonType == 'video') {
      if (lesson.videoTypeWeb == 'system' ||
          lesson.videoTypeWeb == 'html5' ||
          lesson.videoTypeWeb == 'amazon') {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => PlayVideoFromNetwork(
                  courseId: widget.courseId,
                  lessonId: lesson.id!,
                  videoUrl: lesson.videoUrlWeb!)),
        );
      } else if (lesson.videoTypeWeb == 'Vimeo') {
        String vimeoVideoId = lesson.videoUrlWeb!.split('/').last;
        // print(lesson.vimeoVideoId);
        // Navigator.push(
        //     context,
        //     MaterialPageRoute(
        //       builder: (context) => PlayVideoFromVimeoId(
        //           courseId: widget.courseId,
        //           lessonId: lesson.id!,
        //           vimeoVideoId: vimeoVideoId),
        //     ));
        String vimUrl = 'https://player.vimeo.com/video/$vimeoVideoId';
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    VimeoIframe(url: vimUrl)));
      } else {
        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlayVideoFromYoutube(
                  courseId: widget.courseId,
                  lessonId: lesson.id!,
                  videoUrl: lesson.videoUrlWeb!),
            ));
      }
    } else if (lesson.lessonType == 'quiz') {
      // print(lesson.id);
      final token = await SharedPreferenceHelper().getAuthToken();
      final url = '$BASE_URL/api/quiz_mobile_web_view/${lesson.id}/$token';
      // print(_url);
      // Navigator.of(context).pushNamed(WebViewScreen.routeName, arguments: url);
      Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    WebViewScreen(url: url)));
    } else {
      if (lesson.attachmentType == 'iframe') {
        final url = lesson.attachment;
        // Navigator.of(context)
        //     .pushNamed(WebViewScreenIframe.routeName, arguments: url);
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    WebViewScreenIframe(url: url)));
      } else if (lesson.attachmentType == 'description') {
        data = lesson.attachment;
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    FileDataScreen(textData: data, note: lesson.summary!)));
      } else if (lesson.attachmentType == 'txt') {
        final url = '$BASE_URL/uploads/lesson_files/${lesson.attachment}';
        data = await http.read(Uri.parse(url));
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    FileDataScreen(textData: data, note: lesson.summary!)));
      } else {
        final url = '$BASE_URL/uploads/lesson_files/${lesson.attachment}';
        _launchURL(url);
      }
    }
  }

  void _launchURL(lessonUrl) async {
    if (await canLaunch(lessonUrl)) {
      await launch(lessonUrl);
    } else {
      throw 'Could not launch $lessonUrl';
    }
  }

  Widget getLessonSubtitle(Lesson lesson) {
    if (lesson.lessonType == 'video') {
      return CustomText(
        text: lesson.duration,
        fontSize: 12,
      );
    } else if (lesson.lessonType == 'quiz') {
      return RichText(
        text: const TextSpan(
          children: [
            WidgetSpan(
              child: Icon(
                Icons.event_note,
                size: 12,
                color: kSecondaryColor,
              ),
            ),
            TextSpan(
                text: 'Quiz',
                style: TextStyle(fontSize: 12, color: kSecondaryColor)),
          ],
        ),
      );
    } else {
      return RichText(
        text: const TextSpan(
          children: [
            WidgetSpan(
              child: Icon(
                Icons.attach_file,
                size: 12,
                color: kSecondaryColor,
              ),
            ),
            TextSpan(
                text: 'Attachment',
                style: TextStyle(fontSize: 12, color: kSecondaryColor)),
          ],
        ),
      );
    }
  }

  Widget myCourseBody() {
    return _isLoading
        ? const Center(
            child: CircularProgressIndicator(),
          )
        : SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: myLoadedCourse!.length,
                itemBuilder: (ctx, i) {
                  return Column(
                    children: [
                      Card(
                        elevation: 0.3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      child: RichText(
                                        textAlign: TextAlign.left,
                                        text: TextSpan(
                                          text: myLoadedCourse[i].title,
                                          style: const TextStyle(
                                              fontSize: 20,
                                              color: Colors.black),
                                        ),
                                      ),
                                    ),
                                    PopupMenuButton(
                                      onSelected: (value) {
                                        if (value == 'details') {
                                          Navigator.of(context).pushNamed(
                                              CourseDetailScreen.routeName,
                                              arguments: myLoadedCourse[i].id);
                                        } else {
                                          Share.share(myLoadedCourse[i]
                                              .shareableLink
                                              .toString());
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.more_vert,
                                      ),
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'details',
                                          child: Text('Course Details'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'share',
                                          child: Text('Share this Course'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                child: LinearPercentIndicator(
                                  lineHeight: 8.0,
                                  backgroundColor: kBackgroundColor,
                                  percent:
                                      myLoadedCourse[i].courseCompletion! / 100,
                                  progressColor: kRedColor,
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10.0),
                                        child: CustomText(
                                          text:
                                              '${myLoadedCourse[i].courseCompletion}% Complete',
                                          fontSize: 12,
                                          colors: Colors.black54,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10.0),
                                      child: CustomText(
                                        text:
                                            '${myLoadedCourse[i].totalNumberOfCompletedLessons}/${myLoadedCourse[i].totalNumberOfLessons}',
                                        fontSize: 14,
                                        colors: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ListView.builder(
                        key: Key('builder ${selected.toString()}'), //attention
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: sections.length,
                        itemBuilder: (ctx, index) {
                          final section = sections[index];
                          return Card(
                            elevation: 0.3,
                            child: ExpansionTile(
                              key: Key(index.toString()), //attention
                              initiallyExpanded: index == selected,
                              onExpansionChanged: ((newState) {
                                if (newState) {
                                  setState(() {
                                    selected = index;
                                  });
                                } else {
                                  setState(() {
                                    selected = -1;
                                  });
                                }
                              }), //attention
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 5.0,
                                      ),
                                      child: CustomText(
                                        text: HtmlUnescape()
                                            .convert(section.title.toString()),
                                        colors: kDarkGreyColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 5.0),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 1,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: kTimeBackColor,
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 5.0,
                                            ),
                                            child: Align(
                                              alignment: Alignment.center,
                                              child: CustomText(
                                                text: section.totalDuration,
                                                fontSize: 10,
                                                colors: kTimeColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(
                                          width: 10.0,
                                        ),
                                        Expanded(
                                          flex: 1,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: kLessonBackColor,
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 5.0,
                                            ),
                                            child: Align(
                                              alignment: Alignment.center,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: kLessonBackColor,
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                                child: CustomText(
                                                  text:
                                                      '${section.mLesson!.length} Lessons',
                                                  fontSize: 10,
                                                  colors: kDarkGreyColor,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const Expanded(
                                            flex: 2, child: Text("")),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              children: [
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemBuilder: (ctx, index) {
                                    final lesson = section.mLesson![index];
                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          _activeLesson = lesson;
                                        });
                                        lessonAction(_activeLesson!);
                                      },
                                      child: Column(
                                        children: <Widget>[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 10, horizontal: 10),
                                            color: Colors.white60,
                                            width: double.infinity,
                                            child: Row(
                                              children: <Widget>[
                                                Expanded(
                                                  flex: 1,
                                                  child: Checkbox(
                                                      activeColor: kRedColor,
                                                      value:
                                                          lesson.isCompleted ==
                                                                  '1'
                                                              ? true
                                                              : false,
                                                      onChanged: (bool? value) {
                                                        // print(value);

                                                        setState(() {
                                                          lesson.isCompleted =
                                                              value!
                                                                  ? '1'
                                                                  : '0';
                                                          if (value) {
                                                            myLoadedCourse[i]
                                                                    .totalNumberOfCompletedLessons =
                                                                myLoadedCourse[
                                                                            i]
                                                                        .totalNumberOfCompletedLessons! +
                                                                    1;
                                                          } else {
                                                            myLoadedCourse[i]
                                                                    .totalNumberOfCompletedLessons =
                                                                myLoadedCourse[
                                                                            i]
                                                                        .totalNumberOfCompletedLessons! -
                                                                    1;
                                                          }
                                                          var completePerc =
                                                              (myLoadedCourse[i]
                                                                          .totalNumberOfCompletedLessons! /
                                                                      myLoadedCourse[
                                                                              i]
                                                                          .totalNumberOfLessons!) *
                                                                  100;
                                                          myLoadedCourse[i]
                                                                  .courseCompletion =
                                                              completePerc
                                                                  .round();
                                                        });
                                                        Provider.of<MyBundles>(
                                                                context,
                                                                listen: false)
                                                            .toggleLessonCompleted(
                                                                lesson.id!
                                                                    .toInt(),
                                                                value! ? 1 : 0)
                                                            .then((_) => CommonFunctions
                                                                .showSuccessToast(
                                                                    'Course Progress Updated'));
                                                      }),
                                                ),
                                                Expanded(
                                                  flex: 8,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: <Widget>[
                                                      CustomText(
                                                        text: lesson.title,
                                                        fontSize: 14,
                                                        colors: kTextColor,
                                                        fontWeight:
                                                            FontWeight.w400,
                                                      ),
                                                      getLessonSubtitle(lesson),
                                                    ],
                                                  ),
                                                ),
                                                if (lesson.lessonType ==
                                                    'video')
                                                  Expanded(
                                                    flex: 2,
                                                    child: IconButton(
                                                      icon: const Icon(Icons
                                                          .file_download_outlined),
                                                      color: Colors.black45,
                                                      onPressed: () =>
                                                          _initDownload(
                                                              lesson,
                                                              widget.courseId,
                                                              myLoadedCourse[i]
                                                                  .title,
                                                              myLoadedCourse[i]
                                                                  .thumbnail,
                                                              section.title,
                                                              section.id),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(
                                            height: 10,
                                          ),
                                        ],
                                      ),
                                    );
                                    // return Text(section.mLesson[index].title);
                                  },
                                  itemCount: section.mLesson!.length,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          );
  }

  Widget myCourseBodyTwo() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        child: ListView.builder(
          key: Key('builder ${selected.toString()}'), //attention
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sections.length,
          itemBuilder: (ctx, index) {
            final section = sections[index];
            return Card(
              elevation: 0.3,
              child: ExpansionTile(
                key: Key(index.toString()), //attention
                initiallyExpanded: index == selected,
                onExpansionChanged: ((newState) {
                  if (newState) {
                    setState(() {
                      selected = index;
                    });
                  } else {
                    setState(() {
                      selected = -1;
                    });
                  }
                }), //attention
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 5.0,
                        ),
                        child: CustomText(
                          text:
                              HtmlUnescape().convert(section.title.toString()),
                          colors: kDarkGreyColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                color: kTimeBackColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 5.0,
                              ),
                              child: Align(
                                alignment: Alignment.center,
                                child: CustomText(
                                  text: section.totalDuration,
                                  fontSize: 10,
                                  colors: kTimeColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 10.0,
                          ),
                          Expanded(
                            flex: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                color: kLessonBackColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 5.0,
                              ),
                              child: Align(
                                alignment: Alignment.center,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: kLessonBackColor,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: CustomText(
                                    text: '${section.mLesson!.length} Lessons',
                                    fontSize: 10,
                                    colors: kDarkGreyColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Expanded(flex: 2, child: Text("")),
                        ],
                      ),
                    ),
                  ],
                ),
                children: [
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (ctx, index) {
                      final lesson = section.mLesson![index];
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _activeLesson = lesson;
                          });
                          lessonAction(_activeLesson!);
                        },
                        child: Column(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 10),
                              color: Colors.white60,
                              width: double.infinity,
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    flex: 1,
                                    child: Checkbox(
                                        activeColor: kRedColor,
                                        value: lesson.isCompleted == '1'
                                            ? true
                                            : false,
                                        onChanged: (bool? value) {
                                          // print(value);

                                          setState(() {
                                            lesson.isCompleted =
                                                value! ? '1' : '0';
                                            if (value) {
                                              myLoadedCourse[0]
                                                      .totalNumberOfCompletedLessons =
                                                  myLoadedCourse[0]
                                                          .totalNumberOfCompletedLessons! +
                                                      1;
                                            } else {
                                              myLoadedCourse[0]
                                                      .totalNumberOfCompletedLessons =
                                                  myLoadedCourse[0]
                                                          .totalNumberOfCompletedLessons! -
                                                      1;
                                            }
                                            var completePerc = (myLoadedCourse[
                                                            0]
                                                        .totalNumberOfCompletedLessons! /
                                                    myLoadedCourse[0]
                                                        .totalNumberOfLessons!) *
                                                100;
                                            myLoadedCourse[0].courseCompletion =
                                                completePerc.round();
                                          });
                                          Provider.of<MyBundles>(context,
                                                  listen: false)
                                              .toggleLessonCompleted(
                                                  lesson.id!.toInt(),
                                                  value! ? 1 : 0)
                                              .then((_) => CommonFunctions
                                                  .showSuccessToast(
                                                      'Course Progress Updated'));
                                        }),
                                  ),
                                  Expanded(
                                    flex: 8,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        CustomText(
                                          text: lesson.title,
                                          fontSize: 14,
                                          colors: kTextColor,
                                          fontWeight: FontWeight.w400,
                                        ),
                                        getLessonSubtitle(lesson),
                                      ],
                                    ),
                                  ),
                                  if (lesson.lessonType == 'video')
                                    Expanded(
                                      flex: 2,
                                      child: IconButton(
                                        icon: const Icon(
                                            Icons.file_download_outlined),
                                        color: Colors.black45,
                                        onPressed: () => _initDownload(
                                            lesson,
                                            widget.courseId,
                                            myLoadedCourse[0].title,
                                            myLoadedCourse[0].thumbnail,
                                            section.title,
                                            section.id),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(
                              height: 10,
                            ),
                          ],
                        ),
                      );
                      // return Text(section.mLesson[index].title);
                    },
                    itemCount: section.mLesson!.length,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget addonBody() {
    return _isLoading
        ? const Center(
            child: CircularProgressIndicator(),
          )
        : NestedScrollView(
            controller: _scrollController,
            headerSliverBuilder: (context, value) {
              return [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Card(
                      elevation: 0.3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: myLoadedCourse!.length,
                            itemBuilder: (ctx, i) {
                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 1,
                                          child: RichText(
                                            textAlign: TextAlign.left,
                                            text: TextSpan(
                                              text: myLoadedCourse[i].title,
                                              style: const TextStyle(
                                                  fontSize: 20,
                                                  color: Colors.black),
                                            ),
                                          ),
                                        ),
                                        PopupMenuButton(
                                          onSelected: (value) {
                                            if (value == 'details') {
                                              Navigator.of(context).pushNamed(
                                                  CourseDetailScreen.routeName,
                                                  arguments:
                                                      myLoadedCourse[i].id);
                                            } else {
                                              Share.share(myLoadedCourse[i]
                                                  .shareableLink
                                                  .toString());
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.more_vert,
                                          ),
                                          itemBuilder: (_) => [
                                            const PopupMenuItem(
                                              value: 'details',
                                              child: Text('Course Details'),
                                            ),
                                            const PopupMenuItem(
                                              value: 'share',
                                              child: Text('Share this Course'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    child: LinearPercentIndicator(
                                      lineHeight: 8.0,
                                      backgroundColor: kBackgroundColor,
                                      percent:
                                          myLoadedCourse[i].courseCompletion! /
                                              100,
                                      progressColor: kRedColor,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 1,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 10.0),
                                            child: CustomText(
                                              text:
                                                  '${myLoadedCourse[i].courseCompletion}% Complete',
                                              fontSize: 12,
                                              colors: Colors.black54,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 10.0),
                                          child: CustomText(
                                            text:
                                                '${myLoadedCourse[i].totalNumberOfCompletedLessons}/${myLoadedCourse[i].totalNumberOfLessons}',
                                            fontSize: 14,
                                            colors: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 60,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 15.0, vertical: 10),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: false,
                        indicatorColor: kRedColor,
                        padding: EdgeInsets.zero,
                        indicatorPadding: EdgeInsets.zero,
                        labelPadding: EdgeInsets.zero,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: kRedColor),
                        unselectedLabelColor: Colors.black87,
                        labelColor: Colors.white,
                        tabs: [
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.play_lesson,
                                  size: 15,
                                ),
                                Text(
                                  'Lessons',
                                  style: TextStyle(
                                    // fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (liveClassStatus == true)
                            Tab(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.video_call),
                                  Text(
                                    'Live Class',
                                    style: TextStyle(
                                      // fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (courseForumStatus == true)
                            Tab(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.question_answer_outlined),
                                  Text(
                                    'Forum',
                                    style: TextStyle(
                                      // fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                myCourseBodyTwo(),
                if (liveClassStatus == true)
                  LiveClassTabWidget(courseId: widget.courseId),
                if (courseForumStatus == true)
                  ForumTabWidget(courseId: widget.courseId),
              ],
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBarTwo(),
      backgroundColor: kBackgroundColor,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : liveClassStatus == false && courseForumStatus == false
              ? myCourseBody()
              : addonBody(),
    );
  }
}
