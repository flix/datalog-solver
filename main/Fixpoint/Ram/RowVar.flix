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

namespace Fixpoint/Ram {
    pub enum RowVar {
        case Named(String)
    }

    instance ToString[RowVar] {
        def toString(var: RowVar): String = match var {
            case Named(name) => name
        }
    }

    instance Eq[RowVar] {
        def eq(x: RowVar, y: RowVar): Bool = match x <=> y {
            case EqualTo => true
            case _ => false
        }

        def neq(x: RowVar, y: RowVar): Bool = not (x == y)
    }

    instance Order[RowVar] {
        def less(a: RowVar, b: RowVar): Bool = match a <=> b {
            case LessThan => true
            case _ => false
        }

        def lessEqual(a: RowVar, b: RowVar): Bool = match a <=> b {
            case LessThan => true
            case EqualTo => true
            case _ => false
        }

        def greater(a: RowVar, b: RowVar): Bool = match a <=> b {
            case GreaterThan => true
            case _ => false
        }

        def greaterEqual(a: RowVar, b: RowVar): Bool = match a <=> b {
            case GreaterThan => true
            case EqualTo => true
            case _ => false
        }

        def compare(a: RowVar, b: RowVar): Comparison = match (a, b) {
            case (Named(s1), Named(s2)) => s1 <=> s2
        }
    }
}