import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/result_service.dart';
import 'models.dart';

/// Screens depend on this port; database queries stay in the Supabase adapter.
abstract interface class WorkflowRepository {
  Future<Json> profile();
  Future<List<Json>> teachers();
  Future<void> approveTeacher(String id, bool approved);
  Future<List<Course>> courses();
  Future<void> saveCourse(
      {String? id,
      required String code,
      required String title,
      required List<CourseOutcome> outcomes,
      required bool archived});
  Future<List<Offering>> offerings(String courseId);
  Future<void> addOffering(String courseId, String year, String term);
  Future<List<String>> assignments(String offeringId);
  Future<void> assign(String offeringId, String teacherId, bool assigned);
  Future<List<Exam>> exams(String offeringId);
  Future<void> saveExam(Exam exam);
  Future<List<Json>> results(String examId);
  Future<void> saveMarks(ScanContext context, String submissionId, String group,
      Map<String, Map<String, String>> marks,
      {String? resultId, int? revision});
}

class SupabaseWorkflowRepository implements WorkflowRepository {
  final SupabaseClient client;
  SupabaseWorkflowRepository(this.client);
  @override
  Future<Json> profile() async => Json.from(await client
      .from('profiles')
      .select()
      .eq('id', client.auth.currentUser!.id)
      .single());
  @override
  Future<List<Json>> teachers() async =>
      await client.from('profiles').select().order('full_name');
  @override
  Future<void> approveTeacher(String id, bool approved) async {
    await client.from('profiles').update({'approved': approved}).eq('id', id);
  }

  @override
  Future<List<Course>> courses() async =>
      (await client.from('courses').select().order('code'))
          .map(Course.fromJson)
          .toList();
  @override
  Future<void> saveCourse(
      {String? id,
      required String code,
      required String title,
      required List<CourseOutcome> outcomes,
      required bool archived}) async {
    final data = {
      'code': code.trim(),
      'title': title.trim(),
      'archived': archived,
      'outcomes': outcomes.map((c) => c.toJson()).toList()
    };
    if (id == null) {
      await client.from('courses').insert(data);
    } else {
      await client.from('courses').update(data).eq('id', id);
    }
  }

  @override
  Future<List<Offering>> offerings(String courseId) async => (await client
          .from('offerings')
          .select()
          .eq('course_id', courseId)
          .order('academic_year', ascending: false))
      .map(Offering.fromJson)
      .toList();
  @override
  Future<void> addOffering(String courseId, String year, String term) async {
    await client.from('offerings').insert({
      'course_id': courseId,
      'academic_year': year.trim(),
      'term': term.trim()
    });
  }

  @override
  Future<List<String>> assignments(String offeringId) async => (await client
          .from('teaching_assignments')
          .select('teacher_id')
          .eq('offering_id', offeringId))
      .map((e) => e['teacher_id'] as String)
      .toList();
  @override
  Future<void> assign(
      String offeringId, String teacherId, bool assigned) async {
    if (assigned) {
      await client
          .from('teaching_assignments')
          .upsert({'offering_id': offeringId, 'teacher_id': teacherId});
    } else {
      await client
          .from('teaching_assignments')
          .delete()
          .eq('offering_id', offeringId)
          .eq('teacher_id', teacherId);
    }
  }

  @override
  Future<List<Exam>> exams(String offeringId) async => (await client
          .from('exams')
          .select()
          .eq('offering_id', offeringId)
          .order('name'))
      .map(Exam.fromJson)
      .toList();
  @override
  Future<void> saveExam(Exam exam) async {
    final data = {
      'offering_id': exam.offeringId,
      'name': exam.name.trim(),
      'questions': exam.questions.map((q) => q.toJson()).toList(),
      'required_groups': exam.requiredGroups,
      'policy': exam.policy.toJson()
    };
    if (exam.id.isEmpty) {
      await client.from('exams').insert(data);
    } else {
      final rows = await client
          .from('exams')
          .update(data)
          .eq('id', exam.id)
          .eq('revision', exam.revision)
          .select('id');
      if (rows.isEmpty) {
        throw StateError(
            'Exam changed or access was removed. Reload before editing.');
      }
    }
  }

  @override
  Future<List<Json>> results(String examId) async {
    // Page explicitly: PostgREST's default row cap must not truncate reports.
    final rows = <Json>[];
    for (var offset = 0;; offset += 500) {
      final page = await client
          .from('results')
          .select()
          .eq('exam_id', examId)
          .order('id')
          .range(offset, offset + 499);
      rows.addAll(page);
      if (page.length < 500) return rows;
    }
  }

  @override
  Future<void> saveMarks(ScanContext context, String submissionId, String group,
      Map<String, Map<String, String>> marks,
      {String? resultId, int? revision}) async {
    final error = context.validateMarks(group, marks);
    if (error != null) throw FormatException(error);
    await client.rpc('save_verified_marks', params: {
      'p_exam_id': context.exam.id,
      'p_roll_no': context.rollNo,
      'p_submission_id': submissionId,
      'p_table_type': group,
      'p_marks': marks,
      'p_result_id': resultId,
      'p_revision': revision,
      'p_exam_revision': context.exam.revision,
    });
  }
}

/// Keeps the existing scanner's persistence contract intact.
class ExamResultService implements ResultService {
  final WorkflowRepository repository;
  final ScanContext context;
  final String? resultId;
  final int? revision;
  const ExamResultService(this.repository, this.context,
      {this.resultId, this.revision});
  @override
  Future<List<Json>> fetchResults() => repository.results(context.exam.id);
  @override
  Future<void> saveResult(
          {required String rollNo,
          required String submissionId,
          required String tableType,
          required Map<String, Map<String, String>> marks,
          required double grandTotal,
          String? imagePath}) =>
      repository.saveMarks(context, submissionId, tableType, marks,
          resultId: resultId, revision: revision);
}
