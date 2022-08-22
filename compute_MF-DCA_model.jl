#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
"""
compute_energies calculate interaction energy between all pairs of As and Bs in test_seqs
"""

function compute_energies(alignA_Num::Array{Int8,2}, alignB_Num::Array{Int8,2}, test_seqs::Array{Int64,2}, M_test::Int64, W_store::Array{Float64,4}, La::Int64, Lb::Int64)

	#alignA_Num contains alignment A after the aminoacids being converted into numbers, on which the model is trained.
	#alignB_Num contains alignment B after the aminoacids being converted into numbers, on which the model is trained.
	#test_seqs is an array containing the id of sequences in an species, i.e. id of seq A and id of seq B.
	#M_test is the number of sequences in a "test_seqs" (subset of the testing set). .
    #W_store are the Mean Field (MF) couplings of the concatenated A-B alignment.
	#La is the number of aminoacids in the alignment A.
	#Lb is the number of aminoacids in the alignment B.

    AB_energy = zeros(M_test, M_test)

    for i = 1:M_test #to choose the A
        for j = 1:M_test #to choose the B
            for a = 1:La #sites in A
                for b = 1:Lb #sites in B
                    #nb here a < b always, so it is fine to just store half of Wstore.
                    aa1 = alignA_Num[test_seqs[i, 1], a] #aa in A i at site a
                    aa2 = alignB_Num[test_seqs[j, 2], b] #aa in B j at site b
                    AB_energy[i, j] += W_store[a, La + b, aa1, aa2]
                end
            end
        end
    end

    return AB_energy

end



#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
"""
MFCouplings returns the Mean Field (MF) couplings of the concatenated MSA.
"""

function MFCouplings(sim_threshold::Float64, pseudocount_weight::Float64, alignA_Num::Array{Int8,2}, alignB_Num::Array{Int8,2}, dij_A::Array{Int64,2}, dij_B::Array{Int64,2}, training_set::Array{Int64,2}, La::Int64, Lb::Int64)

	#sim_threshold is the similarity threshold.
	#pseudocount_weight is the pseudo-count weight.
	#alignA_Num contains alignment A after the aminoacids being converted into numbers, on which the model is trained.
	#alignB_Num contains alignment B after the aminoacids being converted into numbers, on which the model is trained.
	#dij_A is the Hamming distance between sequences in the alignment A.
	#dij_B is the Hamming distance between sequences in the alignment B.
	#training_set is an array containing the id of species, id of seq A and id of seq B.
	#La is the number of aminoacids in the alignment B.
	#Lb is the number of aminoacids in the alignment A.
	q ::Int8 = 21 #q = 21 is the length of the alphabet.

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
	#The first step is to compute the weights for each sequence and the effective number of sequences.

	L = La + Lb
	M_train = size(training_set, 1) #Mseq_train is the number of sequences in the training set.
	W, Meff = compWeights(dij_A, dij_B, training_set, M_train, L, sim_threshold)

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
	#The second step is to compute the reweighted frequencies.

	Pi_true, Pij_true = compute_freq(alignA_Num, alignB_Num, training_set, W, Meff, M_train, La, Lb, q)

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
	#The third step is to add the pseudocount to frequencies.

	Pi, Pij = pseudocount_freq(Pi_true, Pij_true, L, q, pseudocount_weight)

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
	#The fourth step is to compute the correlation matrix.

	cov_Mat = compute_C(Pi, Pij, L, q)

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
	#The fifth step is to invert the matrix of correlations to get the approximate matrix of direct couplings.

    invC = inv(cov_Mat)

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
	#The sixth step is to make gauge change and store the direct couplings.

	DCA_couplings_zeroSum = zeros(L, L, q, q)

	for i=1:L
		for j=i:L #only fill in the upper triangle of W, because only this part is used (residue pairs where i<j)
        	#get the block of the correlation matrix that corresponds to sites i and j
        	DCA_couplings = ReturnW(invC, i, j, q)
        	#change the gauge in this block to the zero-sum gauge
        	DCA_couplings_zeroSum[i, j, :, :] = change_gauge(DCA_couplings, q)
		end
	end

	return DCA_couplings_zeroSum, Meff

end


#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
"""
ReturnW extracts coupling matrix for columns i and j, i.e. a small block of sixe q x q.
"""

function ReturnW(MFJij::Array{Float64,2}, i::Int64, j::Int64, q::Int8)

    #MFJij is the Mean-Field couplings matrix.
	#i and j represent columns.
	#q = 21 is the length of the alphabet.

    W = zeros(q, q)
	for k = 1:q - 1, l = 1:q - 1
		W[k, l] = MFJij[mapkey(i, k, q), mapkey(j, l, q)]
	end

	return W

end




#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
"""
change_gauge performs gauge change to the zero-sum gauge in the block of interest.
"""

function change_gauge(J_ab::Array{Float64,2}, q::Int8)

	#-------------------------------------------------------------------------------------------------------------------------------------------------------------
	#The first step is to apply the zero-sum gauge to couplings in order to minimizes the Frobenius norm.

	for a = 1:q
		J_a = mean(J_ab[:, a])
		for b = 1:q
			J_ab[b, a] = J_ab[b, a] - J_a
		end
    end

	for b = 1:q
		J_b = mean(J_ab[b, :])
		for a = 1:q
			J_ab[b, a] = J_ab[b, a] - J_b
		end
    end

	return J_ab

end



#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
"""
compute_C computes correlation matrix.
"""

function compute_C(Pi::Array{Float64,2}, Pij::Array{Float64,4}, L::Int64, q::Int8)

	#Pij are the two-point frequencies.
	#Pi are single-point frequencies.
	#L is the number of aminoacids in the joint A-B alignment.
	#q = 21 is the length of the alphabet.

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
	#The first step is to compute the correlation matrix.

    Cov_Matrix = zeros(L * (q - 1), L * (q - 1))

    for i in 1:L, j in 1:L, alpha in 1:q - 1, beta in 1:q - 1
        @inbounds Cov_Matrix[mapkey(i, alpha, q), mapkey(j, beta, q)] = Pij[i, j, alpha, beta] - Pi[i, alpha] * Pi[j, beta]
    end

    return Cov_Matrix

end

#-------------------------------------------------------------------------------------------------------------------------------------------------------
"""
mapkey returns (q - 1) * (i - 1) + alpha.
"""

function mapkey(i::Int64, alpha::Int64, q::Int8)

    return (q - 1) * (i - 1) + alpha

end



#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
"""
pseudocount_freq adds pseudocount to the frequencies.
"""

function pseudocount_freq(Pi_true::Array{Float64,2}, Pij_true::Array{Float64,4}, L::Int64, q::Int8, pseudocount_weight::Float64)

	#Pi_true are the single point frequencies.
	#Pij_true are the two point frequencies.
    #L is the number of aminoacids in the concatenated A-B alignment.
	#q = 21 is the length of the alphabet.
	#pseudocount_weight is the ...

    #---------------------------------------------------------------------------------------------------------------------------------------------------------------
    #The first step is to add the pseudocount to the frequencies.

    Pij = (1.0 - pseudocount_weight) * Pij_true + ((pseudocount_weight / q) / q) * ones(L, L, q, q)
    Pi = (1.0 - pseudocount_weight) * Pi_true + (pseudocount_weight / q) * ones(L, q)

    scra = Matrix{Float64}(I, q, q)

    for i in 1:L, alpha in 1:q, beta in 1:q
		Pij[i, i, alpha, beta] =  (1.0 - pseudocount_weight) * Pij_true[i, i, alpha, beta] + (pseudocount_weight / q) * scra[alpha, beta]
    end

    return Pi, Pij

end


#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
"""
compute_freq computes reweighted frequency counts.
"""

function compute_freq(alignA_Num::Array{Int8,2}, alignB_Num::Array{Int8,2}, training_set::Array{Int64,2}, W::Vector{Float64}, Meff::Float64, M_train::Int64, La::Int64, Lb::Int64, q::Int8)

	#alignA_Num contains alignment A after the aminoacids being converted into numbers, on which the model is trained.
	#alignB_Num contains alignment B after the aminoacids being converted into numbers, on which the model is trained.
	#training_set is an array containing the id of species, id of seq A and id of seq B.
	#W is the reweight of each sequence.
	#M_eff is the effective number of sequences.
    #M_train is the number of sequences in the training set.
    #La is the number of aminoacids in the alignment B.
	#Lb is the number of aminoacids in the alignment A.
	#q = 21 is the length of the alphabet.

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
    #The first step is to compute the one-point reweighted frequencies.

    L = La + Lb ::Int64
	Pi_true = zeros(L, q)

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
    #The first.1 step is to compute the one-point reweighted frequencies on the alignment A.

	@inbounds for i in 1:La, j in 1:M_train
		Pi_true[i, alignA_Num[training_set[j, 2], i]] += W[j]
    end

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
    #The first.2 step is to compute the one-point reweighted frequencies on the alignment B.

	@inbounds for i in 1:Lb, j in 1:M_train
		Pi_true[i + La, alignB_Num[training_set[j, 3], i]] += W[j]
    end

    Pi_true = Pi_true/Meff

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
    #The second step is to compute the two-point reweighted frequencies.

	Pij_true = zeros(L, L, q, q)

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
    #The second.1 step is to compute the two-point reweighted frequencies, but just on the i,j sites of alignment A.

	@inbounds for i in 1:(La - 1), j = i + 1:La, l in 1:M_train
		Pij_true[i, j, alignA_Num[training_set[l, 2], i], alignA_Num[training_set[l, 2], j]] += W[l]
        Pij_true[j, i, alignA_Num[training_set[l, 2], j], alignA_Num[training_set[l, 2], i]] = Pij_true[i, j, alignA_Num[training_set[l, 2], i], alignA_Num[training_set[l, 2], j]]
    end

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
    #The second.2 step is to compute the two-point reweighted frequencies, but on sites i,j that involves both alignment A and B.

	@inbounds for i in 1:La, j = La + 1:L, l in 1:M_train
		Pij_true[i, j, alignA_Num[training_set[l, 2], i], alignB_Num[training_set[l, 3], j - La]] += W[l]
        Pij_true[j, i, alignB_Num[training_set[l, 3], j - La], alignA_Num[training_set[l, 2], i]] = Pij_true[i, j, alignA_Num[training_set[l, 2], i], alignB_Num[training_set[l, 3], j - La]]
    end

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
    #The second.3 step is to compute the two-point reweighted frequencies, but just on the i,j sites of alignment B.

	@inbounds for i in La + 1:(L - 1), j = i + 1:L, l in 1:M_train
		Pij_true[i, j, alignB_Num[training_set[l, 3], i - La], alignB_Num[training_set[l, 3], j - La]] += W[l]
        Pij_true[j, i, alignB_Num[training_set[l, 3], j - La], alignB_Num[training_set[l, 3], i - La]] = Pij_true[i, j, alignB_Num[training_set[l, 3], i - La], alignB_Num[training_set[l, 3], j - La]]
    end

    Pij_true = Pij_true/Meff

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
    #The third step is to ....

    scra = Matrix{Float64}(I, q, q)
    @inbounds for i = 1:L, alpha in 1:q, beta in 1:q
		Pij_true[i, i, alpha, beta] = Pi_true[i, alpha] * scra[alpha, beta]
    end

    return Pi_true, Pij_true

end



#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
"""
compWeights returns the weights (a vector) of each sequence in the dataset and...
...the effective number of sequences.
...These weights take into account how many similar neighbors each sequence has...
...The similarity is given by the parameter "delta" taking values between 0 and 1...
...The values delta = 1 is equivalent to turn down this information.
...The effective number of sequences to compensate for the sampling bias...
...introduced by phylogenetic relations between species.
"""

function compWeights(dij_A::Array{Int64,2}, dij_B::Array{Int64,2}, training_set::Array{Int64,2}, M_train::Int64, L::Int64, sim_threshold::Float64)

	#dij_A is the Hamming distance between sequences in the alignment A.
	#dij_B is the Hamming distance between sequences in the alignment B.
	#training_set is an array containing the id of species, id of seq A and id of seq B.
	#M_train is the number of sequences in the training set.
	#L is the number of amino acids in the concatenated A-B alignment.
	#sim_threshold is the similarity threshold, % of the number of similar residues.

	#---------------------------------------------------------------------------------------------------------------------------------------------------------------
    #The first step is to count the number of sequences with at least "delta * N" identical amino-acids (including itself into this count).

	W::Vector{Float64} = fill(1.0, M_train)

	if sim_threshold != 0.0
		for i in 1:M_train - 1, j in i + 1:M_train
			W[i] += (dij_A[training_set[j, 2], training_set[i, 2]] + dij_B[training_set[j, 3], training_set[i, 3]]) <= sim_threshold * L
			W[j] += (dij_A[training_set[j, 2], training_set[i, 2]] + dij_B[training_set[j, 3], training_set[i, 3]]) <= sim_threshold * L
		end
	end

	W = W.^(-1)
	Meff = sum(W)

    return W, Meff

end



#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------------------------------------------
