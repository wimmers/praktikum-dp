theory Dynamic_Programming
  imports Main "~~/src/HOL/Library/State_Monad"
begin

type_synonym ('s, 'a) state = "'s \<Rightarrow> ('a \<times> 's)"
type_synonym ('param, 'result) dpstate = "('param \<rightharpoonup> 'result, 'result) state"
type_synonym ('param, 'result) dpfun = "'param \<Rightarrow> ('param, 'result) dpstate"

fun return :: "'a \<Rightarrow> ('s, 'a) state" ("\<langle>_\<rangle>") where
  "\<langle>x\<rangle> = (\<lambda>M. (x, M))"
fun get :: "('s, 's) state" where
  "get M = (M, M)"
fun put :: "'s \<Rightarrow> ('s, unit) state" where
  "put M _ = ((), M)"


fun update :: "'param \<Rightarrow> ('param, 'result) dpstate \<Rightarrow> ('param, 'result) dpstate" where
  "update params calcVal = exec {
    v \<leftarrow> calcVal;
    M' \<leftarrow> get;
    _ \<leftarrow> put (M'(params\<mapsto>v));
    \<langle>v\<rangle>
  }"

fun checkmem :: "'param \<Rightarrow> ('param, 'result) dpstate \<Rightarrow> ('param, 'result) dpstate" where
  "checkmem params calcVal = exec {
    M \<leftarrow> get;
    case M params of
      Some v => \<langle>v\<rangle> |
      None => update params calcVal
    }"

definition lift_binary :: "('a \<Rightarrow> 'b \<Rightarrow> 'c) \<Rightarrow> ('M,'a) state \<Rightarrow> ('M,'b) state \<Rightarrow> ('M,'c) state" where
  "lift_binary f s0 s1 \<equiv> exec {v0 \<leftarrow> s0; v1 \<leftarrow> s1; \<langle>f v0 v1\<rangle>}"
definition plus_state (infixl "+\<^sub>s" 65) where "op +\<^sub>s \<equiv> lift_binary (op +)"
definition min\<^sub>s where "min\<^sub>s \<equiv> lift_binary min"
definition max\<^sub>s where "max\<^sub>s \<equiv> lift_binary max"

definition consistentM :: "('param \<Rightarrow> 'result) \<Rightarrow> ('param \<rightharpoonup> 'result) \<Rightarrow> bool" where
  "consistentM f M \<equiv> \<forall>param\<in>dom M. M param = Some (f param)"

definition consistentS :: "('param \<Rightarrow> 'result) \<Rightarrow> 'result \<Rightarrow> ('param, 'result) dpstate \<Rightarrow> bool" where
  "consistentS f v s \<equiv> \<forall>M. consistentM f M \<longrightarrow> fst (s M) = v \<and> consistentM f (snd (s M))"

definition consistentDF :: "('param \<Rightarrow> 'result) \<Rightarrow> ('param, 'result) dpfun \<Rightarrow> bool" where
  "consistentDF f d \<equiv> \<forall>param. consistentS f (f param) (d param)"

lemma consistent_binary:
  assumes c0:"consistentS f v0 s0" and c1:"consistentS f v1 s1"
  shows "consistentS f (g v0 v1) (lift_binary g s0 s1)" (is ?case)
proof -
  {
    fix M assume m0: "consistentM f M"
    let ?gvv="g v0 v1" and ?gss="lift_binary g s0 s1"

    obtain v0' M0 where p0: "s0 M = (v0',M0)" by fastforce
    with c0 m0 have "v0=v0'" and m1: "consistentM f M0" unfolding consistentS_def by fastforce+
    moreover
    obtain v1' M1 where p1: "s1 M0 = (v1',M1)" by fastforce
    with c1 m1 have "v1=v1'" and m2: "consistentM f M1" unfolding consistentS_def by fastforce+
    moreover
    from p0 p1 have pg: "?gss M = (g v0' v1', M1)" unfolding lift_binary_def by simp
    ultimately
    have "fst (?gss M) = ?gvv" "consistentM f (snd (?gss M))" by auto
  }
  thus ?case unfolding consistentS_def by simp
qed

corollary
  consistent_plus: "consistentS f v0 s0 \<Longrightarrow> consistentS f v1 s1 \<Longrightarrow> consistentS f (v0+v1) (s0+\<^sub>ss1)" and
  consistent_min: "consistentS f v0 s0 \<Longrightarrow> consistentS f v1 s1 \<Longrightarrow> consistentS f (min v0 v1) (min\<^sub>s s0 s1)" and
  consistent_max: "consistentS f v0 s0 \<Longrightarrow> consistentS f v1 s1 \<Longrightarrow> consistentS f (max v0 v1) (max\<^sub>s s0 s1)"
  unfolding plus_state_def min\<^sub>s_def max\<^sub>s_def by (fact consistent_binary)+

lemma consistentM_upd: "consistentM f M \<Longrightarrow> consistentM f (M(param\<mapsto>f param))"
  unfolding consistentM_def by auto

lemma consistentS_update:
  assumes prem: "consistentS f (f param) s"
  shows "consistentS f (f param) (update param s)" (is ?thesis)
proof -
  {
    fix M assume cm: "consistentM f M"
    have "fst (update param s M) = f param \<and> consistentM f (snd (update param s M))"
      using prem[unfolded consistentS_def, THEN spec, THEN mp, OF cm]
      by (auto simp: consistentM_upd split: prod.splits)
  }
  thus ?thesis unfolding consistentS_def by auto
qed

lemma consistent_checkmem:
  assumes prem: "consistentS f (f param) s"
  shows "consistentS f (f param) (checkmem param s)" (is ?case)
proof -
  {
    fix M assume *: "consistentM f M"
    have "fst (checkmem param s M) = f param \<and> consistentM f (snd (checkmem param s M))"
      apply (cases "param \<in> dom M")
        using * apply (auto simp: consistentM_def)[]
        using consistentS_update[OF prem] * by (auto simp: consistentS_def)
  }
  thus ?case unfolding consistentS_def by simp
qed

lemma consistent_checkmem':
  assumes "consistentS f v s" "f param = v"
  shows "consistentS f v (checkmem param s)" (is ?case)
  using assms(1) unfolding assms(2)[symmetric] by (rule consistent_checkmem)

lemma consistentS_return:
  "consistentS f v \<langle>v\<rangle>"
  unfolding consistentS_def by simp

text \<open>Generalized version of your fold lemma\<close>
lemma consistent_fold:
  assumes
    "consistentS dp init init'"
    "list_all2 (consistentS dp) xs xs'"
    "f' = lift_binary f"
  shows
    "consistentS dp (fold f xs init) (fold f' xs' init')"
  using assms(2,1,3)
  by (induction arbitrary: init init' rule: list_all2_induct) (auto simp: consistent_binary)

lemma consistent_fold':
  "\<lbrakk>consistentS dp init init';
    \<And>i. i\<in>set idx \<Longrightarrow> consistentS dp (ls i) (ls' i);
    f' = lift_binary f\<rbrakk> \<Longrightarrow>
   consistentS dp (fold f (map ls idx) init) (fold f' (map ls' idx) init')"
  apply (rule consistent_fold)
    apply assumption
  by (induction idx) auto

context
  includes lifting_syntax
begin

lemma consistent_binary_transfer:
  "(consistentS f ===> consistentS f ===> consistentS f) g (lift_binary g)"
  by (auto simp: rel_fun_def intro: consistent_binary)

lemma consistent_fold_alt:
  assumes
    "consistentS dp init init'"
    "list_all2 (consistentS dp) xs xs'"
  shows
    "consistentS dp (fold f xs init) (fold (lift_binary f) xs' init')"
  supply [transfer_rule] = consistent_binary_transfer assms
  by transfer_prover

text \<open>
  We could prove a stronger version of this lemma by replacing @{term "op ="}
  by another relation.
\<close>
lemma consistent_fold_map:
  "\<lbrakk>consistentS dp init init';
    (op = ===> consistentS dp) ls ls';
    f' = lift_binary f\<rbrakk> \<Longrightarrow>
   consistentS dp (fold f (map ls idx) init) (fold f' (map ls' idx) init')"
  apply (rule consistent_fold)
    apply assumption
  subgoal premises prems
    supply [transfer_rule] = prems
    by transfer_prover
  .

text \<open>And finally a 'big-bang version' of the last two proofs combined.\<close>
lemma consistent_fold_map_alt:
  assumes
    "consistentS dp init init'"
    "(op = ===> consistentS dp) ls ls'"
  shows
    "consistentS dp (fold f (map ls idx) init) (fold (lift_binary f) (map ls' idx) init')"
  supply [transfer_rule] = consistent_binary_transfer assms
  by transfer_prover

lemma consistent_cond_alt:
  assumes "consistentS dp v0 s0" "consistentS dp v1 s1"
  shows "consistentS dp (if b then v0 else v1) (if b then s0 else s1)"
  supply [transfer_rule] = assms
  by transfer_prover

text \<open>
  Conclusion: the default parametricity rules for \<open>map\<close> and \<open>if _ then _ else\<close> are too weak.
  Fold works out of the box.
\<close>

end (* End of lifting syntax *)

lemma consistent_cond:
  assumes "b \<Longrightarrow> consistentS dp v0 s0" "\<not>b \<Longrightarrow> consistentS dp v1 s1"
  shows "consistentS dp (if b then v0 else v1) (if b then s0 else s1)"
  using assms by auto

lemmas consistency_rules =
  consistent_cond consistent_fold' consistent_max consistent_plus consistent_checkmem'
  consistentS_return

(* Fib *)

fun fib :: "nat \<Rightarrow> nat" where
"fib 0 = 0" |
"fib (Suc 0) = 1" |
"fib (Suc(Suc n)) = fib(Suc n) + fib n"

fun fib' fib'' :: "(nat, nat) dpfun" where
  "fib' param = checkmem param (fib'' param)" |
  "fib'' 0 = \<langle>0\<rangle>" |
  "fib'' (Suc 0) = \<langle>1\<rangle>" |
  "fib'' (Suc (Suc n)) = fib' (Suc n) +\<^sub>s fib' n"

lemma "consistentDF fib fib'"
  unfolding consistentDF_def
  apply (rule allI)
  apply (induct_tac param rule: fib.induct)

    apply (simp only: fib'.simps fib''.simps fib.simps)
    apply (assumption | rule consistency_rules)+
    apply (simp_all only: fib.simps)

   apply (simp only: fib'.simps fib''.simps fib.simps)
   apply (assumption | rule consistency_rules)+
   apply (simp_all only: fib.simps)

  apply (simp only: fib'.simps fib''.simps fib.simps)
  apply (assumption | rule consistency_rules)+
  apply (simp_all only: fib.simps)
  done

(* Bellman Ford *)

context
  fixes W :: "nat \<Rightarrow> nat \<Rightarrow> int"
    and n :: nat
begin

text \<open>Could also be primrec\<close>
text \<open>Dimensionality as parameter\<close>

fun bf :: "(nat\<times>nat) \<Rightarrow> int" where
  "bf (0, j) = W 0 j" |
  "bf (Suc k, j) = fold min [bf (k, i) + W i j. i\<leftarrow>[0..<n]] (bf (k, j))"

fun bf' bf'' :: "(nat\<times>nat, int) dpfun" where
  "bf' params = checkmem params (bf'' params)" |
  "bf'' (0, j) = \<langle>W 0 j\<rangle>" |
  "bf'' (Suc k, j) = fold min\<^sub>s [bf' (k, i) +\<^sub>s \<langle>W i j\<rangle>. i\<leftarrow>[0..<n]] (bf' (k, j))"

lemma "consistentDF bf bf'"
  apply (unfold consistentDF_def, rule allI, induct_tac rule: bf.induct)
   apply (simp only: bf.simps bf'.simps bf''.simps)
   apply (assumption | rule consistency_rules)+
   apply (simp only: bf.simps)

  apply (simp only: bf.simps bf'.simps bf''.simps)
    apply (assumption | rule consistency_rules)+
   apply (simp only: min\<^sub>s_def)
  apply (simp only: bf.simps)
  done

end

text \<open>Not primrec\<close>
text \<open>Dimensionality given by i, j\<close>
fun ed :: "(nat\<times>nat) \<Rightarrow> nat" where
  "ed (0, 0) = 0" |
  "ed (0, Suc j) = Suc j" |
  "ed (Suc i, 0) = Suc i" |
  "ed (Suc i, Suc j) = min (ed (i, j) + 2) (min (ed (Suc i, j) + 1) (ed (i, Suc j) + 1))"

fun ed' ed''  :: "(nat\<times>nat, nat) dpfun" where
  "ed' params = checkmem params (ed'' params)" |
  "ed'' (0, 0) = \<langle>0\<rangle>" |
  "ed'' (0, Suc j) = \<langle>Suc j\<rangle>" |
  "ed'' (Suc i, 0) = \<langle>Suc i\<rangle>" |
  "ed'' (Suc i, Suc j) = min\<^sub>s (ed' (i, j) +\<^sub>s \<langle>2\<rangle>) (min\<^sub>s (ed' (Suc i, j) +\<^sub>s \<langle>1\<rangle>) (ed' (i, Suc j) +\<^sub>s \<langle>1\<rangle>))"
thm minus_nat_inst.minus_nat

lemma "consistentDF ed ed'"
  by (unfold consistentDF_def, rule allI, induct_tac rule: ed.induct)
     (auto simp only: ed.simps ed'.simps ed''.simps intro!: consistent_checkmem' consistentS_return consistent_min consistent_plus)

term "(a :: nat) - (b :: nat)"

context
  fixes w :: "nat \<Rightarrow> nat"
begin

fun su :: "(nat\<times>nat) \<Rightarrow> nat" where
  "su (0, W) = (if W < w 0 then 0 else w 0)" |
  "su (Suc i, W) = (if W < w (Suc i)
    then su (i, W)
    else max (su (i, W)) (w i + su (i, W - w i)))"

fun su' su'' :: "(nat\<times>nat, nat) dpfun" where
  "su' params = checkmem params (su'' params)" |
  "su'' (0, W) = (if W < w 0 then \<langle>0\<rangle> else \<langle>w 0\<rangle>)" |
  "su'' (Suc i, W) = (if W < w (Suc i)
    then su' (i, W)
    else max\<^sub>s (su' (i, W)) (\<langle>w i\<rangle> +\<^sub>s su' (i, W - w i)))"

lemma "consistentDF su su'"
  apply (unfold consistentDF_def, rule allI, induct_tac rule: su.induct)
   apply (simp only: su.simps su'.simps su''.simps)
   apply (assumption | rule consistency_rules)+
   apply (simp only: su.simps)

  apply (simp only: su.simps su'.simps su''.simps)
  apply (assumption | rule consistency_rules)+
  apply (simp only: su.simps)
  done
end

context
  fixes v :: "nat \<Rightarrow> nat"
    and p :: "nat \<Rightarrow> nat"
  assumes p_lt: "p (Suc j) < Suc j"
begin


text \<open>Dimensionality given by i\<close>
function wis :: "nat \<Rightarrow> nat" where
  "wis 0 = 0" |
  "wis (Suc i) = max (wis (p (Suc i)) + v i) (wis i)"
  by pat_completeness auto
termination
  by (relation "(\<lambda>p. size p) <*mlex*> {}") (auto intro: wf_mlex mlex_less simp: p_lt)

function wis' wis'' :: "(nat, nat) dpfun" where
  "wis' params = checkmem params (wis'' params)" |
  "wis'' 0 = \<langle>0\<rangle>" |
  "wis'' (Suc i) = max\<^sub>s (wis' (p (Suc i)) +\<^sub>s \<langle>v i\<rangle>) (wis' i)"
  by pat_completeness auto
termination
  by (relation "case_sum size size <*mlex*> case_sum (\<lambda>x. Suc 0) (\<lambda>x. 0) <*mlex*> {}")
     (auto simp: mlex_leq mlex_less wf_mlex p_lt)

lemma nat_le_induct:
  assumes "P 0" "\<And>x. (\<And>y. y<Suc x \<Longrightarrow> P y) \<Longrightarrow> P (Suc x)"
    shows "P a"
proof (cases a)
  case 0 thus ?thesis using assms(1) by simp next
  case Suc
  have "\<And>b. b\<le>a \<Longrightarrow> P b"
    using assms by (induction a) (auto elim: le_SucE)
  thus ?thesis by simp
qed

lemma "consistentDF wis wis'"
  apply (unfold consistentDF_def, rule allI, induct_tac param rule: wis.induct)
   apply (simp only: wis.simps wis'.simps wis''.simps)
   apply (assumption | rule consistency_rules)+
   apply (simp only: wis.simps)

  apply (simp only: wis.simps wis'.simps wis''.simps)
  apply (assumption | rule consistency_rules)+
  by (simp only: wis.simps)

end