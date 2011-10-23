from cpython cimport bool
from libc.stdlib cimport malloc, calloc, free
from libc.math cimport log

cdef float MIN_FLOAT = float('-inf')

cdef float csum(float* tab, int n):
        cdef int i=0
        cdef float res=0
        while i<n:
                res+=tab[i]
                i+=1
        return res

cdef class hmm:
    cdef public int nStates, nObs
    cdef bool logdomain
    cdef float* pi
    cdef float** t
    cdef float** e

    def __init__(self, int nStates, int nObs):
        """HMM constructor.
        
        Parameters
        ----------
        nStates: non-negative integer
            Number of hidden states.
        nObs: non-negative integer
            Number of possible observed values."""
        self.pi= <float*> calloc(nStates, sizeof(float))
        self.t= <float**> malloc(nStates*sizeof(float*))
        self.e= <float**> malloc(nObs*sizeof(float*))
        cdef int i=0
        for i in range(nStates):
                self.t[i]= <float*> calloc(nStates, sizeof(float))
                self.e[i]= <float*> calloc(nObs, sizeof(float))
                i+=1
        
        self.nStates=nStates
        self.nObs=nObs
        self.logdomain=False

    def learn(self, list observations, list ground_truths):
        """Learns from a list of observation sequences and their associated ground truth.

        Parameters
        ----------
        observations: list of list of integers in {0, ..., nObs-1}
            List of observed sequences.
        ground_truths: list of list of integers in {0, ..., nStates-1}
            Associated list of ground truths.""" 
        self.__init__(self.nStates, self.nObs)
        N=len(observations)
        cdef int i, j
        for i in xrange(N):
            o=observations[i]
            t=ground_truths[i]

            self.pi[t[0]]+=1
            for j in range(len(t)-1):
                self.t[t[j]][t[j+1]]+=1 #possible loss of precision
                self.e[t[j]][o[j]]+=1   #rewrite with int** types
            j+=1
            self.e[t[j]][o[j]]+=1

        cdef float Zt, Ze
        for i in range(self.nStates):
            self.pi[i]/=N
            Zt= csum(self.t[i], self.nStates)
            Ze= csum(self.e[i], self.nObs)
            for j in range(self.nStates):
                self.t[i][j]/=max(1., Zt)
            for j in range(self.nObs):
                self.e[i][j]/=max(1., Ze)

    def __convert_to_log(self):
        """Convers the internal probability tables in the log domain."""
        cdef int i, j
        for i in range(self.nStates):
            if self.pi[i]>0:
                self.pi[i]=log(self.pi[i])
            else:
                self.pi[i]=MIN_FLOAT
            for j in range(self.nStates):
                if self.t[i][j]>0:
                    self.t[i][j]=log(self.t[i][j])
                else:
                    self.t[i][j]=MIN_FLOAT
            for j in range(self.nObs):
                if self.e[i][j]>0:
                    self.e[i][j]=log(self.e[i][j])
                else:
                    self.e[i][j]=MIN_FLOAT
        self.logdomain=True

    def viterbi(self, list observation):
        """Viterbi inference of the highest likelihood hidden states sequence given the observations. Time complexity is O(|observation|*nStates^2).
        
        Parameters
        ----------
        observation: List of integers in {0, ..., nObs-1}.

        Returns
        -------
        seq: List of integers in {0, ..., nStates-1}
            Highest likelihood infered sequence of hidden states.
        loglike: negative float
            Loglikelihood of the model for that sequence."""
        cdef int N=len(observation)
        cdef float** tab = <float**> malloc(N*sizeof(float*))
        cdef int** backtrack = <int**> malloc(N*sizeof(float*))
        cdef int i, j, s, smax
        cdef float maxval, cs, llike
        for i in xrange(N):
                tab[i] = <float*> malloc(self.nStates*sizeof(float))
                backtrack[i] = <int*> malloc(self.nStates*sizeof(int))
        
        if not self.logdomain:
            self.__convert_to_log()

        for i in range(self.nStates):
            tab[0][i]=self.e[i][observation[0]]+self.pi[i]
        
        for i in xrange(1,N):
            for j in range(self.nStates):
                smax=-1
                maxval=MIN_FLOAT
                for s in range(self.nStates):
                    cs=tab[i-1][s]+self.t[s][j]
                    if cs>maxval:
                        smax=s
                        maxval=cs
                tab[i][j]=self.e[j][observation[i]]+maxval
                backtrack[i][j]=smax

        smax=-1
        llike=MIN_FLOAT
        for s in range(self.nStates):
            if llike<tab[N-1][s]:
                llike=tab[N-1][s]
                smax=s

        best=[0]*N
        best[N-1]=smax
        for i in xrange(N-2, -1, -1):
            best[i]=backtrack[i+1][best[i+1]]

        #free memory before leaving
        for i in xrange(N):
                free(tab[i])
                free(backtrack[i])
        free(tab)
        free(backtrack)

        return best, llike

        def __del__(self):
                cdef int i=0
                for i in range(nStates):
                        free(self.t[i])
                        free(self.e[i])
                        i+=1
                free(self.t)
                free(self.e)
                free(self.pi)