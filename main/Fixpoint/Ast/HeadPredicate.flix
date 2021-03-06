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
namespace Fixpoint/Ast {
    pub enum HeadPredicate[v] {
        case HeadAtom(PredSym, List[HeadTerm[v]], SourceLocation)
    }

    def headVars(head: HeadPredicate[v]): Set[VarSym] = match head {
        case HeadAtom(_, terms, _) => htermVars(terms)
    }

    def htermVars[v](terms: List[HeadTerm[v]]): Set[VarSym] =
        List.foldLeft((acc, t) -> match t {
            case HeadTerm.Var(var, _) => Set.insert(var, acc)
            case HeadTerm.App(_, args, _) => Set.union(acc, htermVars(args))
            case HeadTerm.Lit(_, _) => acc
        }, Set.empty(), terms)

    instance ToString[HeadPredicate[v]] with [v : ToString] {
        def toString(head: HeadPredicate[v]): String = match head {
            case HeadAtom(predSym, terms, _) =>
                let ts = List.map(ToString.toString, terms) |> String.intercalate(", ");
                "${predSym}(${ts})"
        }
    }
}