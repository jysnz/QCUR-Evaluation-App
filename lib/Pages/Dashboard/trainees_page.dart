import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class TraineesPage extends StatefulWidget {
  const TraineesPage({super.key});

  @override
  State<TraineesPage> createState() => _TraineesPageState();
}

class _TraineesPageState extends State<TraineesPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _trainees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTrainees();
  }

  Future<void> _fetchTrainees() async {
    setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('trainees')
          .select()
          .order('full_name');
      setState(() {
        _trainees = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addTrainee() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('ADD TRAINEE', style: TextStyle(color: kAccent, fontWeight: FontWeight.w900, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: kForeground),
              decoration: _inputDecoration('Full Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              style: const TextStyle(color: kForeground),
              decoration: _inputDecoration('Email (Optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCEL')),
          TechnicalButton(label: 'ADD', onTap: () => Navigator.of(context).pop(true)),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      try {
        await supabase.from('trainees').insert({
          'full_name': nameController.text.trim(),
          'email': emailController.text.trim().isEmpty ? null : emailController.text.trim(),
          'creator_id': supabase.auth.currentUser!.id,
        });
        _fetchTrainees();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBackground,
        title: const Text('TRAINEE ROSTER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2)),
      ),
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          Padding(
            padding: const EdgeInsets.all(kPadding),
            child: Column(
              children: [
                Expanded(
                  child: TechnicalCard(
                    padding: const EdgeInsets.all(0),
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator(color: kAccent))
                        : _trainees.isEmpty
                            ? const Center(child: Text('NO TRAINEES FOUND', style: TextStyle(color: kForegroundMuted)))
                            : ListView.separated(
                                itemCount: _trainees.length,
                                separatorBuilder: (context, index) => const Divider(height: 1, color: Colors.white10),
                                itemBuilder: (context, index) {
                                  final trainee = _trainees[index];
                                  return ListTile(
                                    title: Text(trainee['full_name'], style: const TextStyle(color: kForeground, fontWeight: FontWeight.bold)),
                                    subtitle: trainee['email'] != null ? Text(trainee['email'], style: const TextStyle(color: kForegroundMuted)) : null,
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                      onPressed: () async {
                                        await supabase.from('trainees').delete().eq('id', trainee['id']);
                                        _fetchTrainees();
                                      },
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
                const SizedBox(height: 16),
                TechnicalButton(
                  label: 'Add Trainee',
                  icon: Icons.person_add,
                  onTap: _addTrainee,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kAccent, width: 1)),
    );
  }
}
