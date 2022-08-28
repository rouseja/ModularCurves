//the following function checks if rank J0(N)(Q) = rank J0(N)+(Q) as suggested by Philippe
IsRankOfALQuotEqual := function(N)
  J := JZero(N);
  w := AtkinLehnerOperator(J,N);
  if(Nrows(Matrix(w)) eq 0) then
    printf "non-existent Atkin-Lehner operator";
    return false;
  end if;
  Jmin := ConnectedKernel(1+w);
  return not IsZeroAt(LSeries(Jmin),1);
end function;

// Compute the rank of J0(N)+ using Kolyvagin-Logachev. Will
// throw an error if the analytic rank for any newform appears 
// to be >1.
// I believe this is Steffen's code.
function rank_J0Nplus(N : Lprec := 30, printlevel := 0)
  NF := Newforms(CuspForms(Gamma0(N),2));
  errors := [];
  pl := printlevel;

  for f in [t[1] : t  in NF | AtkinLehnerEigenvalue(t[1], N) eq 1] do
    if pl gt 1 then printf "The newform is %o, \n", qExpansion(f, 20); end if;
    if pl gt 1 then printf "defined over %o. \n\b", NumberField(BaseRing(f)); end if;
    L := LSeries(ModularAbelianVariety(f));
    d := Degree(NumberField(BaseRing(f)));
    if not IsZeroAt(L, 1) then return 0, [0: i in [1..d]]; end if;
    Lseries := [LSeries(f : Embedding := func<x | Conjugates(x)[i] >) : i in [1..d]];
    rank := 0;
    i := 0;

    for L in Lseries do 
      LSetPrecision(L, Lprec);
      if pl gt 1 then "checking the functional equation for conjugate",i; end if;
      assert IsZero(CFENew(L));
      taylor := LTaylor(L, 1, 1);  
      if pl gt 0 then 
        printf "The Taylor expansion of the L-function of %o at s=1 is \n%o\n", f, taylor;
      end if;
      if IsZero(Coefficient(taylor, 0)) then 
        coeff := Coefficient(taylor, 1);
        if Abs(coeff) lt 10^-3 then // might be 0
          error "rank seems to be larger than g -- this is not implemented";
        else 
          rank +:= 1;
        end if;
      end if;
      Append(~errors, coeff);
      i +:= 1;
    end for; // L in Lseries
  end for; // f in ...
  return rank, errors;
end function;

//This function computes J_X(F_p) for curve X

JacobianFp := function(X)
	CC, phi, psi := ClassGroup(X); //Algorithm of Hess
	Z := FreeAbelianGroup(1);
	degr := hom<CC->Z | [ Degree(phi(a))*Z.1 : a in OrderedGenerators(CC)]>;
	JFp := Kernel(degr); // This is isomorphic to J_X(\F_p).
	return JFp, phi, psi;
end function;

//This function computes the discriminant of the field a place is defined over.

discQuadPlace := function(P);
        assert Degree(P) eq 2;
        K := ResidueClassField(P);
    	D := Discriminant(MaximalOrder(K));

    	if IsDivisibleBy(D, 4) then
           D := D div 4;
    	end if;

        return D;
end function;

// This is part of code written by Ozman and Siksek and used by Box in https://arxiv.org/pdf/1906.05206.pdf.
// X is a projective curve over rationals,
// p prime of good reduction,
// D divisor on X,
// This reduces to a divisor on X/F_p.

reduce := function(X,Xp,D);
	if Type(D) eq DivCrvElt then
		decomp := Decomposition(D);
		return &+[ pr[2]*$$(X, Xp, pr[1]) : pr in decomp]; // Reduce the problem to reducing places.
	end if;

	R<[x]> := CoordinateRing(AmbientSpace(X));
        assert Type(D) eq PlcCrvElt;

	if (Degree(D) eq 1) and (#{Degree(xx) : xx in x} eq 1) then
		P := D;
		m := Rank(R);
		KX := FunctionField(X);
		inds := [i : i in [1..m] | &and[Valuation(KX!(x[j]/x[i]), P) ge 0 : j in [1..m]]];	
		assert #inds ne 0;
		i := inds[1];
		PP := [Evaluate(KX!(x[j]/x[i]), P) : j in [1..m]];
		denom := LCM([Denominator(d) : d in PP]);
		PP := [Integers()!(denom*d) : d in PP];
		g := GCD(PP);
		PP := [d div g : d in PP];
		Fp := BaseRing(Xp);
		PP := Xp![Fp!d : d in PP];
		return Place(PP);	
	end if;

	I := Ideal(D);
	Fp := BaseRing(Xp);
	p := Characteristic(Fp);
	B := Basis(I) cat DefiningEquations(X);
	m := Rank(CoordinateRing(X));

	assert Rank(CoordinateRing(Xp)) eq m;

	R := PolynomialRing(Integers(),m);
	BR := [];

	for f in B do
		g := f*p^-(Minimum([Valuation(c, p) : c in Coefficients(f)]));
		g := g*LCM([Denominator(c) : c in Coefficients(g)]);
		Append(~BR, g);
	end for;

	J := ideal<R | BR>;
	J := Saturation(J, R!p);
	BR := Basis(J);
	Rp := CoordinateRing(AmbientSpace(Xp));

	assert Rank(Rp) eq m;

	BRp := [Evaluate(f, [Rp.i : i in [1..m]]) : f in BR];
	Jp := ideal<Rp| BRp>;
	Dp := Divisor(Xp, Jp);
	return Dp;
end function;
	

// divs are a bunch of known effective divisors,
// P0 is a base point of degree 1,
// p>2 is a prime of good reduction.
// This determines an abstract abelian group Ksub
// isomorphic to the group spanned by [D-deg(D) P_0] 
// where D runs through the elements of divs.  
// It also returns a subset divsNew such that [[D-deg(D) P_0] : D in divsNew]
// generates the same subgroup.
// It also determines a homomorphism 
// h : \Z^r --> Ksub
// where divsNew=[D_1,..,D_r]
// and h([a_1,..,a_r]) is the image of 
// a_1 (D_1-deg(D_1) P_0)+\cdots + a_r (D_r-deg(D_r) P_0)
// in Ksub.

findGenerators:=function(X,divs,P0,p);
	fn:=func<A,B| Degree(A)-Degree(B)>;
	Sort(~divs,fn); // Sort the divisors by degree.
	assert IsPrime(p);
	assert p ge 3;
	Xp:=ChangeRing(X,GF(p));

	// assert IsSingular(Xp) eq false;
	// Now we know that
	// J_X(Q)-->J_X(\F_p) is injective (we're assuming rank 0).

	C,phi,psi:=ClassGroup(Xp);
	Z:=FreeAbelianGroup(1);
	degr:=hom<C->Z | [ Degree(phi(a))*Z.1 : a in OrderedGenerators(C)]>;
	A:=Kernel(degr); // This is isomorphic to J_X(\F_p).
	Pp0:=reduce(X,Xp,P0);
	divsRed:=[reduce(X,Xp,D) : D in divs];
	divsRedA:=[psi(D-Degree(D)*Pp0) : D in divsRed]; // The image of the divisors in A;
	Ksub1:=sub<A | divsRedA>; // The subgroup of J(\F_p) generated by
							// [D-deg(D)*P_0] with D in divs.	
	// Next we eliminate as many of the divisors as possible
	// while keeping the same image.
	r:=#divs;
	inds:=[i : i in [1..r]];
	i:=r+1;
	repeat
		i:=i-1;
		indsNew:=Exclude(inds,i);
		if sub<A | [divsRedA[j] : j in indsNew]> eq Ksub1 then
			inds:=indsNew;
		end if;
	until i eq 1;
	divsNew:=[divs[j] : j in inds];
	divsRedA:=[divsRedA[j] : j in inds];
	r:=#divsNew;	
	Zr:=FreeAbelianGroup(r);
	h:=hom<Zr->A | divsRedA>;
	Ksub:=Image(h); // Stands from known subgroup.
	assert Ksub eq Ksub1;
	h:=hom<Zr->Ksub | [ Ksub!h(Zr.i) :  i in [1..r] ]>;
	// Restrict the codomain of h so that it is equal to Ksub.
	bas:=[Eltseq(i@@h) : i in OrderedGenerators(Ksub)];
	return h,Ksub,bas,divsNew;
end function;

function TorsionBound(X, BadPrimes : LowerBound := 0, PrimesBound := 20)
  torsionBound := 0;
  for p in PrimesUpTo(PrimesBound) do
    if p in BadPrimes then
      continue;
    end if;
    Fp := GF(p);
    try
	    Xp := ChangeRing(X, Fp);
    catch e
      continue; 
    end try;
    torsionBound := Gcd(torsionBound, #TorsionSubgroup(ClassGroup(Xp)));
    // TODO: one can optimize this exploiting the group structure
    if torsionBound eq LowerBound then
      return torsionBound;
    end if;
  end for;
  return torsionBound;
end function;

function GetTorsion(N, XN, XN_Cusps)

	if IsPrime(N) then
		// sanity check
		assert #XN_Cusps eq 2;

		Dtor := Divisor(XN_Cusps[1]) - Divisor(XN_Cusps[2]);
		order := Integers()!((N - 1) / GCD(N - 1, 12));
		
		A := AbelianGroup([order]);
		divs := [Dtor];

	else
		p := 3;
		while IsDivisibleBy(N, p) do
			p := NextPrime(p);
		end while;

		// compute the cuspidal torsion subgroup (= J(Q)_tors assuming the generalized Ogg conjecture)
		h, Ksub, bas, divsNew := findGenerators(XN, [Place(cusp) : cusp in XN_Cusps], Place(XN_Cusps[1]), p);

		// Ksub == abstract group isomorphic to cuspidal
		// "It also returns a subset divsNew such that [[D-deg(D) P_0] : D in divsNew] generates the same subgroup."

		A := Ksub;

		D := [Divisor(divsNew[i]) - Divisor(XN_Cusps[1]) : i in [1..#divsNew]];
		divs := [&+[coeffs[i] * D[i] : i in [1..#coeffs]] : coeffs in bas];
	end if;

	return A, divs;

end function;
