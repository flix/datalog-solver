/*
 * Copyright 2021 Benjamin Dahse
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

use Fixpoint/Ram.{RamStmt, RelOp, RelSym, RamTerm, BoolExp, RowVar};
use Fixpoint/Ast.{Constraint, BodyPredicate, BodyTerm, HeadTerm, Polarity, PredSym, VarSym};
use Fixpoint/Ast.Constraint.Constraint;
use Fixpoint/Ast.HeadPredicate.HeadAtom;
use Fixpoint/Ast.BodyPredicate.{BodyAtom, GuardAtom};
use Fixpoint/Ast.PredSym.PredSym;

namespace Fixpoint {
    pub def compile[v : ToString](cs: List[Constraint[v]], strat: Map[PredSym, Int32]): RamStmt[v] =
        let facts = facts(cs) |> List.map(compileRule) |> List.fold;
        let strata =
            Map.invert(strat) |>
            Map.map(restrict(cs) >> compileStratum) |>
            Map.valuesOf |>
            List.fold;
        List.fold(facts :: strata :: Nil)

    /// Compile all rules to be computed in a stratum to RAM, by using semi-naive evaluation
    /// as a code generator.
    def compileStratum[v : ToString](stratum: List[Constraint[v]]): RamStmt[v] =
        let idb = idb(stratum) |> Set.toList;
        let eval = List.map(compileRule, stratum) |> List.fold;
        let mergeDelta =
            List.map(match PredSym(relName, _) -> {
                RamStmt.Merge(RelSym.Full(relName), RelSym.Delta(relName))
            }, idb) |>
            List.fold;
        let purge =
            List.map(match PredSym(relName, _) -> {
                RamStmt.Purge(RelSym.New(relName))
            }, idb) |>
            List.fold;
        let evalIncr = List.map(compileRuleIncr, stratum) |> List.fold;
        let mergeNew =
            List.map(match PredSym(relName, _) -> {
                RamStmt.Merge(RelSym.New(relName), RelSym.Full(relName))
            }, idb) |>
            List.fold;
        let assign =
            List.map(match PredSym(relName, _) -> {
                RamStmt.Assign(RelSym.Delta(relName), RelSym.New(relName))
            }, idb) |>
            List.fold;
        let loopTest = List.map(match PredSym(relName, _) -> BoolExp.Empty(RelSym.Delta(relName)), idb);
        let loopBody = List.fold(purge :: evalIncr :: mergeNew :: assign :: Nil);
        let fixpoint = RamStmt.Until(loopTest, loopBody);
        List.fold(eval :: mergeDelta :: fixpoint :: Nil)

    /// Compile rule into a join loop.
    def compileRule[v : ToString](rule: Constraint[v]): RamStmt[v] = match rule {
        case Constraint(HeadAtom(PredSym(headPred, _), headTerms, _), body, _) =>
            let augBody = augmentBody(body);
            let env = unifyVars(augBody);
            let join = joinTerms(env, augBody);
            let ramTerms = List.map(compileHeadTerm(env), headTerms);
            let projection = RelOp.Project(ramTerms, RelSym.Full(headPred));
            let insert =
                List.foldRight(match (atom, rowVar, _) -> match (isLast, acc) -> match atom {
                    case GuardAtom(_) => (isLast, acc)
                    case BodyAtom(PredSym(pred, _), _, _, _) =>
                        if (isLast)
                            (false, RelOp.Search(rowVar, RelSym.Full(pred), join, acc))
                        else
                            (false, RelOp.Search(rowVar, RelSym.Full(pred), Nil, acc))
                }, (true, projection), positiveAtoms(augBody)) |>
                snd |>
                RamStmt.Insert;
            let comment = RamStmt.Comment(ToString.toString(rule));
            List.fold(comment :: insert :: Nil)
    }

    def compileRuleIncr[v : ToString](rule: Constraint[v]): RamStmt[v] = match rule {
        case Constraint(HeadAtom(PredSym(headPred, _), headTerms, _), body, _) =>
            let augBody = augmentBody(body);
            let positiveAtoms = positiveAtoms(augBody);
            /// Compile rule into an incremental join loop where delta designates the focused atom.
            let compile = delta -> {
                let env = unifyVars(augBody);
                let join = joinTerms(env, augBody);
                let ramTerms = List.map(compileHeadTerm(env), headTerms);
                let projection = RelOp.Project(ramTerms, RelSym.New(headPred));
                List.foldRight(match (atom, rowVar, i) -> match (isLast, acc) -> match atom {
                    case GuardAtom(_) => (isLast, acc)
                    case BodyAtom(PredSym(pred, _), _, _, _) =>
                        let relSym = if (i == delta) {
                            RelSym.Delta(pred)
                        } else {
                            RelSym.Full(pred)
                        };
                        let where = if (isLast) {
                            BoolExp.NotMemberOf(ramTerms, RelSym.Full(headPred)) :: join
                        } else {
                            Nil
                        };
                        (false, RelOp.Search(rowVar, relSym, where, acc))
                }, (true, projection), positiveAtoms) |>
                snd |>
                RamStmt.Insert
            };
            let deltas = List.map(match (_, _, i) -> compile(i), positiveAtoms) |> List.fold;
            let comment = RamStmt.Comment(ToString.toString(rule));
            List.fold(comment :: deltas :: Nil)
    }

    def compileHeadTerm(env: Map[VarSym, RamTerm[v]], term: HeadTerm[v]): RamTerm[v] = match term {
        case HeadTerm.Var(var, _) => env |> Map.get(var) |> unwrap
        case HeadTerm.Lit(v, _) => RamTerm.Lit(v)
        case HeadTerm.App(f, args, _) => RamTerm.App(f, List.map(compileHeadTerm(env), args))
    }

    def compileBodyTerm(env: Map[VarSym, RamTerm[v]], term: BodyTerm[v]): RamTerm[v] = match term {
        case BodyTerm.Var(var, _) => env |> Map.get(var) |> unwrap
        case BodyTerm.Lit(v, _) => RamTerm.Lit(v)
    }

    /// Augment body atoms with row variables and indices.
    def augmentBody(body: List[BodyPredicate[v]]): List[(BodyPredicate[v], RowVar, Int32)] =
        List.mapWithIndex(atom -> i -> match atom {
            case GuardAtom(_) => (atom, RowVar.Named("Guard$${i}"), i)
            case BodyAtom(predSym, _, _, _) => (atom, RowVar.Named("${predSym}$${i}"), i)
        }, body)

    /// Return all positive atoms present in body.
    def positiveAtoms(body: List[(BodyPredicate[v], RowVar, Int32)]): List[(BodyPredicate[v], RowVar, Int32)] =
        List.filter(match (atom, _, _) -> match atom {
            case BodyAtom(_, Polarity.Positive, _, _) => true
            case BodyAtom(_, Polarity.Negative, _, _) => false
            case GuardAtom(_) => false
        }, body)

    /// Unifies each variable that occurs in a rule body with an attribute
    /// corresponding to a positive atom where the variable is a term.
    def unifyVars(body: List[(BodyPredicate[v], RowVar, Int32)]): Map[VarSym, RamTerm[v]] =
        List.foldLeft(acc -> match (atom, rowVar, _) -> match atom {
            case GuardAtom(_) => acc
            case BodyAtom(_, Polarity.Negative, _, _) => acc
            case BodyAtom(_, Polarity.Positive, terms, _) =>
                List.mapWithIndex(term -> j -> match term {
                    case BodyTerm.Var(var, _) => Map.singleton(var, RamTerm.Attribute(rowVar, j))
                    case BodyTerm.Lit(_, _) => Map#{}
                }, terms) |>
                List.foldLeft(Map.union, acc)
        }, Map#{}, body)

    /// Equates every term in a positive body atom with an attribute
    /// and declares that terms in negative body atoms are not in the corresponding relations.
    def joinTerms(env: Map[VarSym, RamTerm[v]], body: List[(BodyPredicate[v], RowVar, Int32)]): List[BoolExp[v]] =
        List.flatMap(match (atom, rowVar, _) -> match atom {
            case BodyAtom(_, Polarity.Positive, terms, _) =>
                List.mapWithIndex(term -> j -> {
                    let ramTerm = compileBodyTerm(env, term);
                    BoolExp.Eq(RamTerm.Attribute(rowVar, j), ramTerm)
                }, terms)
            case BodyAtom(PredSym(relName, _), Polarity.Negative, terms, _) =>
                let ramTerms = List.map(compileBodyTerm(env), terms);
                BoolExp.NotMemberOf(ramTerms, RelSym.Full(relName)) :: Nil
            case GuardAtom(f, terms, _) =>
                BoolExp.Guard(f, List.map(compileBodyTerm(env), terms)) :: Nil
        }, body)

    def unwrap(o: Option[a]): a = match o {
        case Some(a) => a
        case None => ???
    }

    /// Restrict a constraint system to those rules whose head predicate belongs to a given domain.
    def restrict(cs: List[Constraint[v]], domain: Set[PredSym]): List[Constraint[v]] =
        let headPred = match Constraint(HeadAtom(headSym, _, _), _, _) -> headSym;
        let memberOf = xs -> x -> Set.memberOf(x, xs);
        let body = match Constraint(_, atoms, _) -> atoms;
        let notEmpty = xs -> not List.isEmpty(xs);
        List.filter(body >> notEmpty, cs) |> List.filter(headPred >> memberOf(domain))

    def idb(cs: List[Constraint[v]]): Set[PredSym] =
        let headPred = acc -> c -> match c {
            case Constraint(_, Nil, _) => acc
            case Constraint(HeadAtom(headSym, _, _), _, _) => Set.insert(headSym, acc)
        };
        List.foldLeft(headPred, Set#{}, cs)

    def facts(cs: List[Constraint[v]]): List[Constraint[v]] =
        let body = match Constraint(_, atoms, _) -> atoms;
        List.filter(body >> List.isEmpty, cs)
}
